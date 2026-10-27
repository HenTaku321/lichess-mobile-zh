#!/usr/bin/env node
// Translate the puzzle opening names lichess serves, and cache them in `assets/openings.zh.json`.
//
// Why this exists: the app's "puzzles by opening" list (`view/puzzle/opening_screen.dart`) and the
// opening titles on the puzzle tab and the puzzle screen are all rendered from
// `/training/openings`, whose names are English in every language — see
// `translation/source/puzzle.xml`, which covers themes only, and lila itself, which has no
// translation source for opening names at all. The payload is cached by the app for a day
// (`puzzleOpeningsProvider` uses `withClientCacheFor`), so overlaying it on the server would be
// masked anyway; the overlay belongs in the app.
//
// The output is keyed by the English name rather than by opening key, so it is content-addressed:
// a renamed opening misses and falls back to English, keys changing is a non-event, and a name
// shared by several families ("Closed", "Exchange Variation") is stored once. Each name carries
// the families it appears under as context for the translator — the name alone is often all there
// is ("Main Line"), but the composition is what tells 变例 from 变着.
//
// The `keys` section is derived, not translated: it is the same Chinese names composed the way the
// app composes them (`'${family}: ${child}'` in `flatOpeningsListProvider`), so the offline
// saved-opening list, which only ever has a key, can show Chinese too. It is rebuilt from `names`
// on every run, so the two sections cannot drift.
//
// Usage:
//   LLM_BASE_URL=... LLM_API_KEY=... LLM_MODEL=... \
//     node scripts/gen-openings-zh.mjs [options]
//
// Options:
//   --dry-run        translate and report, write nothing
//   --limit <n>      stop after n batches (cheap smoke test)
//   --force          retranslate every name, ignoring the cache
//   --input <file>   read the lichess payload from a file instead of fetching it
//
// Env (same names as the Go proxy and translate-zh.mjs, so one gateway serves both). Only needed
// when there is something left to translate: a run that only recomposes `keys` — a rerun after a
// hand-edit, which is the normal way to correct an entry — reads the cache and writes the file:
//   LLM_BASE_URL, LLM_API_KEY, LLM_MODEL, LLM_BATCH_LIMIT, LLM_BATCH_CHARS, LLM_TIMEOUT_SECONDS,
//   LLM_REASONING_EFFORT
//
// The fetched payload is cached in `scripts/tmp/openings.json` (gitignored), so reruns do not ask
// lichess for 70 KB again; delete it to refetch.

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs'
import { fileURLToPath } from 'url'
import { dirname, join } from 'path'

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROOT = join(__dirname, '..')
const PAYLOAD = join(__dirname, 'tmp', 'openings.json')
const OUTPUT = join(ROOT, 'assets', 'openings.zh.json')
const OPENINGS_URL = 'https://lichess.org/training/openings'

const cfg = {
  baseUrl: (process.env.LLM_BASE_URL ?? '').replace(/\/+$/, ''),
  apiKey: process.env.LLM_API_KEY ?? '',
  model: process.env.LLM_MODEL ?? '',
  batchLimit: Number(process.env.LLM_BATCH_LIMIT ?? 30),
  batchChars: Number(process.env.LLM_BATCH_CHARS ?? 4000),
  timeoutMs: Number(process.env.LLM_TIMEOUT_SECONDS ?? 180) * 1000,
  // Sent as `reasoning_effort` on every request; `off` omits the field entirely. See the same
  // note in `gen-practice-zh.mjs`: against the gateway this runs on, leaving thinking on costs
  // minutes per batch for the same translations.
  reasoningEffort: (process.env.LLM_REASONING_EFFORT ?? 'none').trim(),
}
if (cfg.reasoningEffort === 'off') cfg.reasoningEffort = ''

const opt = { dryRun: false, limit: Infinity, force: false, input: null }
const argv = process.argv.slice(2)
for (let i = 0; i < argv.length; i++) {
  const a = argv[i]
  if (a === '--dry-run') opt.dryRun = true
  else if (a === '--force') opt.force = true
  else if (a === '--limit') opt.limit = Number(argv[++i])
  else if (a === '--input') opt.input = argv[++i]
  else if (a === '--help' || a === '-h') {
    console.log(readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').slice(2, 32).join('\n'))
    process.exit(0)
  } else {
    console.error(`Unknown option: ${a}`)
    process.exit(1)
  }
}

/** Whether the gateway is configured well enough to send a batch. */
function llmConfigured() {
  return cfg.baseUrl !== '' && cfg.model !== '' && (cfg.apiKey !== '' || /localhost|127\.0\.0\.1/.test(cfg.baseUrl))
}

// ---- the English names to translate ------------------------------------------

/**
 * The payload is `{openings: [{family, openings: [{key, name, count}]}]}`: 122 families, each with
 * its variations. A variation's name is relative ("Closed"), which is why the family it sits under
 * travels with it — and why the key, which the app also displays offline, is composed from both.
 */
async function loadPayload() {
  if (opt.input) return JSON.parse(readFileSync(opt.input, 'utf8'))
  if (existsSync(PAYLOAD)) return JSON.parse(readFileSync(PAYLOAD, 'utf8'))
  const res = await fetch(OPENINGS_URL, { headers: { accept: 'application/json' } })
  if (!res.ok) throw new Error(`lichess answered ${res.status} for ${OPENINGS_URL}`)
  const text = await res.text()
  mkdirSync(dirname(PAYLOAD), { recursive: true })
  writeFileSync(PAYLOAD, text, 'utf8')
  return JSON.parse(text)
}

/** One `{name, under}` per distinct English name, `under` being the families it appears in. */
function collectEntries(payload) {
  const families = payload.openings ?? payload
  const under = new Map()
  // Families first: fifteen names are both a family and a variation of another one, and as a
  // family a name stands on its own — the variation entries that share it add no context.
  for (const { family } of families) if (!under.has(family.name)) under.set(family.name, [])
  for (const { family, openings = [] } of families) {
    for (const child of openings) {
      const contexts = under.get(child.name) ?? []
      if (!contexts.includes(family.name)) contexts.push(family.name)
      under.set(child.name, contexts)
    }
  }
  return { families, entries: [...under].map(([name, contexts]) => ({ name, under: contexts })) }
}

function loadCache() {
  if (opt.force || !existsSync(OUTPUT)) return new Map()
  const parsed = JSON.parse(readFileSync(OUTPUT, 'utf8'))
  const cache = new Map()
  for (const [english, chinese] of Object.entries(parsed.names ?? {})) {
    if (typeof chinese === 'string' && chinese.trim() !== '') cache.set(english, chinese)
  }
  return cache
}

// ---- batches ----------------------------------------------------------------

/** Shortest names first, so a `--limit` smoke test covers 封闭变例 before 尼亚兹梅特季诺夫. */
function makeBatches(entries) {
  const sorted = [...entries].sort((a, b) => a.name.length - b.name.length)
  const batches = []
  let batch = []
  let chars = 0
  for (const entry of sorted) {
    if (batch.length >= cfg.batchLimit || chars + entry.name.length > cfg.batchChars) {
      if (batch.length > 0) batches.push(batch)
      batch = []
      chars = 0
    }
    batch.push(entry)
    chars += entry.name.length
  }
  if (batch.length > 0) batches.push(batch)
  return batches
}

const SYSTEM_PROMPT = `You are a professional chess writer localizing the Lichess app's opening names from English into Simplified Chinese, using standard Mainland Chinese chess terminology.

Input: a JSON array of objects. Each has a "name" — the name of a chess opening or one of its variations — and "under", the list of opening families the name appears in. An empty "under" means the name is a family name, complete on its own; a non-empty one means it is a variation whose name is relative to those families.

Requirements:
- Use the standard Chinese chess vocabulary: 开局 opening, 变例 variation, 防御 defense, 弃兵 gambit, 反弃兵 countergambit, 进攻 attack, 体系 system, 主变 main line, 封闭变例 closed, 开放变例 open, 古典变例 classical, 兑换变例 exchange, 前进变例 advance, 对称变例 symmetrical, 侧翼出动 fianchetto.
- Surnames and place names take their established Chinese form where chess literature has one (Sicilian 西西里, French 法兰西, Caro-Kann 卡罗-卡恩, Najdorf 纳伊多夫, Alapin 阿拉平, Taimanov 泰马诺夫, Grünfeld 格林菲尔德, Nimzowitsch 尼姆佐维奇, Réti 列蒂), and a plain transliteration otherwise. Keep diacritics out of the Chinese.
- Name like a Chinese opening name, not like a description: as short as the source, no sentence, no trailing punctuation, no quotes, no explanation.
- Keep "Lichess" and "Stockfish" in Latin script if they occur.
- Translate every entry — never return an empty string, and never leave one in English.`

// The task itself has to be restated in the user turn, not only in the system message: the
// gateway this runs against reads a user turn holding nothing but a JSON array as material to be
// worked on and answers with a question instead of the translations. Measured on 2026-10-11, see
// the same note in `gen-practice-zh.mjs`.
const USER_INSTRUCTION = `Translate the "name" field of each object in this JSON array into Simplified Chinese.
Return ONLY a JSON array of STRINGS, of the SAME LENGTH and in the SAME ORDER as the input array — one Chinese name per input, nothing else.

`

async function translateBatchOnce(batch) {
  const res = await fetch(`${cfg.baseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(cfg.apiKey ? { authorization: `Bearer ${cfg.apiKey}` } : {}),
    },
    // No max_tokens: a reasoning model emits its thinking before any content, and a cap sized for
    // the translation would cut it off mid-thought and return nothing.
    body: JSON.stringify({
      model: cfg.model,
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user', content: USER_INSTRUCTION + JSON.stringify(batch, null, 1) },
      ],
      temperature: 0.2,
      ...(cfg.reasoningEffort ? { reasoning_effort: cfg.reasoningEffort } : {}),
    }),
    signal: AbortSignal.timeout(cfg.timeoutMs),
  })
  if (!res.ok) {
    const body = (await res.text()).slice(0, 300)
    const err = new Error(`LLM HTTP ${res.status}: ${body}`)
    // A rejected key or a malformed model name fails the same way on the next attempt.
    err.retryable = res.status === 429 || res.status >= 500
    throw err
  }
  const json = await res.json()
  const content = json?.choices?.[0]?.message?.content
  if (typeof content !== 'string' || content.trim() === '') {
    throw new Error(
      `LLM response had no message content (finish_reason=${json?.choices?.[0]?.finish_reason})`,
    )
  }
  const text = content.replace(/^```(?:json)?\s*/m, '').replace(/```\s*$/, '')
  const start = text.indexOf('[')
  const end = text.lastIndexOf(']')
  if (start === -1 || end === -1) throw new Error(`LLM did not return a JSON array: ${content.slice(0, 300)}`)
  const parsed = JSON.parse(text.slice(start, end + 1))
  // Asking for an array of strings is not always enough: the same instruction is answered with an
  // array of the input objects, `name` translated, often enough to be worth reading either.
  const names = Array.isArray(parsed)
    ? parsed.map((entry) =>
        typeof entry === 'string'
          ? entry
          : entry && typeof entry.name === 'string'
            ? entry.name
            : null,
      )
    : []
  // Position is the only mapping there is, so a wrong length is not repairable: which returned
  // name belongs to which input would be a guess. Ask again instead.
  if (names.length !== batch.length || names.some((n) => n === null || n.trim() === '')) {
    const bad = names.findIndex((n) => n === null || n.trim() === '')
    throw new Error(
      `LLM returned ${names.length} usable names for ${batch.length} inputs` +
        (bad >= 0 ? ` (first bad entry: ${JSON.stringify(parsed[bad]).slice(0, 80)})` : ''),
    )
  }
  return new Map(batch.map((entry, i) => [entry.name, names[i]]))
}

async function translateBatch(batch) {
  let lastErr
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      return await translateBatchOnce(batch)
    } catch (e) {
      lastErr = e
      if (e.retryable === false || attempt === 3) break
      console.log(`  batch of ${batch.length} failed (${e.message.slice(0, 100)}); retrying`)
    }
  }
  throw lastErr
}

// ---- main -------------------------------------------------------------------

/**
 * The names composed the way the app composes them, for the one place that has nothing but a key:
 * the offline saved-opening list (`_SavedOpeningTile`). Only entries whose parts are both
 * translated are emitted, so a partial overlay stays half English rather than half wrong.
 */
function deriveKeys(families, cache) {
  const keys = {}
  for (const { family, openings = [] } of families) {
    const familyName = cache.get(family.name)
    if (familyName === undefined) continue
    keys[family.key] = familyName
    for (const child of openings) {
      const childName = cache.get(child.name)
      if (childName === undefined) continue
      keys[child.key] = `${familyName}: ${childName}`
    }
  }
  return keys
}

// Only names that are still in the payload are kept, so the file cannot accumulate dead entries.
function writeOutput(entries, families, cache) {
  const names = {}
  for (const entry of entries.map((e) => e.name).sort()) {
    const chinese = cache.get(entry)
    if (chinese !== undefined) names[entry] = chinese
  }
  const out = { names, keys: deriveKeys(families, cache) }
  if (!opt.dryRun) writeFileSync(OUTPUT, JSON.stringify(out, null, 1) + '\n', 'utf8')
  return out
}

async function main() {
  const { families, entries } = collectEntries(await loadPayload())
  const cache = loadCache()
  const todo = entries.filter((e) => !cache.has(e.name))
  console.log(
    `${families.length} families, ${entries.length} distinct names, ${cache.size} cached, ${todo.length} to translate`,
  )

  // Checked here rather than up front: a run with nothing left to translate only recomposes the
  // derived `keys` section — what a rerun after a hand-edit does — and must not demand a gateway.
  if (todo.length > 0 && !llmConfigured()) {
    console.error('LLM_BASE_URL and LLM_MODEL must be set to translate (LLM_API_KEY for hosted providers)')
    process.exit(1)
  }

  const batches = makeBatches(todo)
  let done = 0
  for (const batch of batches) {
    if (done >= opt.limit) {
      console.log(`--limit ${opt.limit} reached, stopping`)
      break
    }
    const started = Date.now()
    const translated = await translateBatch(batch)
    for (const [english, chinese] of translated) cache.set(english, chinese)
    done += 1
    // Written after every batch rather than once at the end: a run over a hosted gateway is one
    // 502 away from losing everything, and a file that is already partly translated makes the
    // rerun resume instead of start over.
    writeOutput(entries, families, cache)
    console.log(
      `  batch ${done}/${batches.length}: ${batch.length} names in ${((Date.now() - started) / 1000).toFixed(1)}s` +
        `  e.g. ${JSON.stringify(batch[0].name)} -> ${JSON.stringify(cache.get(batch[0].name))}`,
    )
  }

  const out = writeOutput(entries, families, cache)
  const translatedNames = Object.keys(out.names).length
  if (opt.dryRun) {
    console.log(`dry run: would write ${translatedNames} names and ${Object.keys(out.keys).length} keys`)
    return
  }
  console.log(`wrote ${translatedNames} names and ${Object.keys(out.keys).length} keys to ${OUTPUT}`)
  const untranslated = entries.filter((e) => out.names[e.name] === undefined)
  if (untranslated.length > 0) {
    console.log(`note: ${untranslated.length} names left untranslated (the app falls back to English)`)
  }
}

main().catch((e) => {
  console.error(e.message ?? e)
  process.exit(1)
})
