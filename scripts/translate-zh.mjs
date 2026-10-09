#!/usr/bin/env node
// Batch-retranslate the zh-CN UI strings with an LLM, then let a human review
// the diff before it is committed.
//
// Why this exists: the upstream zh-CN translations are not missing — coverage of
// the keys the app actually uses is ~100% — but a good part of them read as
// machine-translated chess prose ("Bronstein delay" -> "Bronstein 延时",
// "Add to study" -> "添加到研习"). This script rewrites the string *values* only,
// refining the upstream Chinese rather than retranslating blind, and its output
// is committed so the build stays deterministic and no API key lands in CI.
//
// Only the 26 modules listed in gen-arb.mjs are touched; anything else never
// reaches an ARB and would be wasted work. The model never sees raw markup:
// see xml.mjs for how the round-trip is kept lossless.
//
// Usage:
//   LLM_BASE_URL=... LLM_API_KEY=... LLM_MODEL=... \
//     node scripts/translate-zh.mjs [options]
//
// Options:
//   --only <substr>   only modules whose name contains <substr>
//   --all             translate every key, not just the ones the app references
//   --dry-run         translate and report, write nothing
//   --limit <n>       stop after n batches (cheap smoke test)
//
// Env (same names as the Go proxy so one deployment can serve both):
//   LLM_BASE_URL, LLM_API_KEY, LLM_MODEL, LLM_BATCH_LIMIT, LLM_BATCH_CHARS,
//   LLM_TIMEOUT_SECONDS

import { readFileSync, writeFileSync, renameSync, existsSync, readdirSync } from 'fs'
import { fileURLToPath } from 'url'
import { dirname, join } from 'path'
import { parseXml, replaceValues, samePlaceholders, placeholders, lineBreaks } from './xml.mjs'

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROOT = join(__dirname, '..')
const SRC_DIR = join(ROOT, 'translation', 'source')
const DEST_DIR = join(ROOT, 'translation', 'dest')
const LANG = 'zh-CN'

const MODULES = [
  'mobile',
  'activity',
  'arena',
  'broadcast',
  'challenge',
  'contact',
  'coordinates',
  'learn',
  'patron',
  'perfStat',
  'practice',
  'preferences',
  'puzzle',
  'puzzleTheme',
  'recap',
  'search',
  'settings',
  'site',
  'storm',
  'streamer',
  'study',
  'team',
  'tfa',
  'timeago',
  'ublog',
  'variant',
]

const cfg = {
  baseUrl: process.env.LLM_BASE_URL ?? '',
  apiKey: process.env.LLM_API_KEY ?? '',
  model: process.env.LLM_MODEL ?? '',
  batchLimit: Number(process.env.LLM_BATCH_LIMIT ?? 30),
  batchChars: Number(process.env.LLM_BATCH_CHARS ?? 6000),
  timeoutMs: Number(process.env.LLM_TIMEOUT_SECONDS ?? 180) * 1000,
}

const opt = { only: null, dryRun: false, limit: 0, all: false }
const argv = process.argv.slice(2)
for (let i = 0; i < argv.length; i++) {
  const a = argv[i]
  if (a === '--only') opt.only = argv[++i]
  else if (a === '--dry-run') opt.dryRun = true
  else if (a === '--limit') opt.limit = Number(argv[++i])
  else if (a === '--all') opt.all = true
  else if (a === '-h' || a === '--help') {
    console.log(readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').slice(0, 25).join('\n'))
    process.exit(0)
  } else {
    console.error(`unknown option: ${a} (try --help)`)
    process.exit(2)
  }
}

if (!cfg.baseUrl || !cfg.model) {
  console.error('LLM_BASE_URL and LLM_MODEL must be set (LLM_API_KEY for hosted providers)')
  process.exit(2)
}

// ---- units ------------------------------------------------------------------

/** @typedef {{ id:number, module:string, name:string, quantity:string|null,
 *              source:string, existing:string, comment:string, maxLength:number|null }} Unit */

const SYSTEM_PROMPT = `You are a professional software localizer translating the Lichess chess app's user interface from English into Simplified Chinese.

Input: a JSON array of objects with fields id, name, quantity, source, existing, comment.
- "source" is the authoritative English string.
- "existing" is the current Chinese translation. It may be mediocre or wrong. Treat it as a strong hint about intended meaning, terminology and length — improve or replace it, but stay consistent with it where it is already fine.
- "comment" is the developer's note on where the string appears; use it to disambiguate.
- "name" is the translation key; it also hints at context.
- "quantity" is the plural category ("one"/"other") when present. Simplified Chinese has no grammatical plural, so both categories may translate identically — that is expected.

Return ONLY a JSON array of {"id": <number>, "text": <chinese>} with the same ids, in the same order.

Requirements:
- Use standard Mainland Chinese chess terminology: 王 king / 后 queen / 车 rook / 象 bishop / 马 knight / 兵 pawn; 将军 check, 将杀 checkmate, 和棋 draw, 悔棋 takeback, 升变 promotion, 战术 tactics, 局面 position, 开局 opening, 残局 endgame, 等级分 rating, 对局 game, 棋谱/研习 study.
- Keep brand and product names in Latin script: Lichess, Stockfish, Puzzle Storm, Puzzle Streak, Puzzle Racer, Bronstein, Fischer, Arena.
- Format placeholders are load-bearing and must survive unchanged: %s, %1$s, %2$s, %3$s, %4$s and %% must each appear exactly as many times in your output as in the source. You may reorder %N$s placeholders when Chinese word order demands it, but never drop, add or renumber one.
- Preserve the escape sequence \\n (literally backslash-n) exactly where the source has it.
- Respect a comment that states a maximum length; short UI labels should read as 2-4 characters where Chinese allows.
- Do not add punctuation, trailing colons or full stops that the source lacks.
- Return Chinese for every string. Only a pure brand name, a pure placeholder, or an untranslatable token should come back unchanged.`

/** @param {Unit[]} units */
function buildUserPrompt(units) {
  return JSON.stringify(
    units.map((u) => ({
      id: u.id,
      name: u.name,
      quantity: u.quantity,
      source: u.source,
      existing: u.existing,
      comment: u.comment,
    })),
  )
}

function parseResult(raw) {
  let s = String(raw).trim()
  const fence = s.match(/```(?:json)?\s*([\s\S]*?)```/)
  if (fence) s = fence[1].trim()
  const start = s.indexOf('[')
  const end = s.lastIndexOf(']')
  if (start === -1 || end === -1 || end < start) {
    throw new Error(`model did not return a JSON array: ${s.slice(0, 200)}`)
  }
  const arr = JSON.parse(s.slice(start, end + 1))
  if (!Array.isArray(arr)) throw new Error('model returned non-array JSON')
  const out = new Map()
  for (const item of arr) {
    if (item && typeof item.id === 'number' && typeof item.text === 'string') {
      out.set(item.id, item.text)
    }
  }
  return out
}

/** @param {Unit[]} units @returns {Promise<Map<number,string>>} */
async function translateBatch(units) {
  const headers = { 'content-type': 'application/json' }
  if (cfg.apiKey) headers.authorization = `Bearer ${cfg.apiKey}`
  const res = await fetch(`${cfg.baseUrl.replace(/\/+$/, '')}/chat/completions`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      model: cfg.model,
      temperature: 0.2,
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user', content: buildUserPrompt(units) },
      ],
    }),
    signal: AbortSignal.timeout(cfg.timeoutMs),
  })
  if (!res.ok) throw new Error(`LLM HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`)
  const json = await res.json()
  const content = json?.choices?.[0]?.message?.content
  if (typeof content !== 'string') throw new Error('LLM response had no message content')
  return parseResult(content)
}

// ---- validation -------------------------------------------------------------
//
// These failures are all silent at runtime — a dropped %s throws on first render,
// an over-long label is clipped, an emptied string disappears — so reject the
// translation and keep the upstream one instead of trusting the model.

function reject(unit, text) {
  if (text.trim().length === 0) return 'empty'
  if (!samePlaceholders(unit.source, text)) {
    return `placeholders ${placeholders(unit.source).join(',') || '-'} -> ${placeholders(text).join(',') || '-'}`
  }
  if (lineBreaks(text) !== lineBreaks(unit.source)) return 'line-break count changed'
  if (unit.maxLength != null && [...text].length > unit.maxLength) {
    return `over maxLength ${unit.maxLength}`
  }
  return null
}

// ---- collection -------------------------------------------------------------

// Only 44% of the corpus is reachable from the app: `contact` (0/83 keys),
// `streamer` (0/45), `ublog` (0/50), `learn` (25/173) and `study` (51/183) are
// lichess.org website copy that no Flutter screen ever reads. Translating those
// costs money and review attention for zero visible effect, so by default the
// run is narrowed to the keys the app actually references. --all overrides it.
const ARB_KEY_RE = /l10n\.([A-Za-z0-9_]+)/g

/** @returns {Set<string>} l10n getter names referenced anywhere under lib/ */
function usedL10nKeys() {
  const keys = new Set()
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const p = join(dir, entry.name)
      if (entry.isDirectory()) walk(p)
      else if (entry.name.endsWith('.dart') && !entry.name.endsWith('.g.dart') && !entry.name.endsWith('.freezed.dart')) {
        for (const m of readFileSync(p, 'utf8').matchAll(ARB_KEY_RE)) keys.add(m[1])
      }
    }
  }
  walk(join(ROOT, 'lib'))
  return keys
}

/** Mirrors fixKey() in scripts/gen-arb.mjs: this maps a translation name to the
 * Dart getter the app would call for it. */
function arbKey(module, name) {
  const fixed = name.replace(/\./g, '_')
  return module === 'site' ? fixed : module + fixed.charAt(0).toUpperCase() + fixed.slice(1)
}

/** @returns {{units: Unit[], skipped: number}|null} */
function collectUnits(module, idBase, used) {
  const srcPath = join(SRC_DIR, `${module}.xml`)
  const zhPath = join(DEST_DIR, module, `${LANG}.xml`)
  if (!existsSync(srcPath) || !existsSync(zhPath)) return null

  const src = parseXml(readFileSync(srcPath, 'utf8'))
  const zh = parseXml(readFileSync(zhPath, 'utf8'))

  const srcStrings = new Map(src.strings.map((s) => [s.name, s]))
  const srcPlurals = new Map(src.plurals.map((p) => [p.name, p]))

  // Iterate the *Chinese* document, not the source: only a node that already
  // exists can be rewritten in place. Chinese derives every plural category from
  // the single "other" item, so a source "one" with no Chinese counterpart is
  // correctly skipped rather than newly invented.
  const units = []
  let skipped = 0
  const push = (name, quantity, source, existing, comment, maxLength) => {
    // `used` gates on the *base* name: every plural category of a used plural
    // shares one getter, so it is kept or dropped as a whole.
    if (used && !used.has(arbKey(module, name))) {
      skipped++
      return
    }
    units.push({
      id: idBase + units.length,
      module,
      name,
      quantity,
      source,
      existing,
      comment,
      maxLength: maxLength ?? null,
    })
  }

  for (const s of zh.strings) {
    const en = srcStrings.get(s.name)
    if (!en) continue
    push(s.name, null, en.text, s.text, en.attrs.comment ?? '', en.attrs.maxLength)
  }
  for (const p of zh.plurals) {
    const en = srcPlurals.get(p.name)
    if (!en) continue
    for (const item of p.items) {
      const enItem =
        en.items.find((i) => i.quantity === item.quantity) ??
        en.items.find((i) => i.quantity === 'other') ??
        en.items[0]
      if (!enItem) continue
      const comment = [en.attrs.comment, `plural: ${item.quantity}`].filter(Boolean).join(' | ')
      push(p.name, item.quantity, enItem.text, item.text, comment, en.attrs.maxLength)
    }
  }
  return { units, skipped }
}

/** Chunks by both a unit count and a character budget: `site` has strings an
 * order of magnitude longer than `mobile`'s, so a count-only batch would
 * overflow the context on the long modules and waste it on the short ones. */
function chunk(units) {
  const out = []
  let cur = []
  let chars = 0
  for (const u of units) {
    const cost = u.source.length + u.existing.length + 120
    if (cur.length > 0 && (cur.length >= cfg.batchLimit || chars + cost > cfg.batchChars)) {
      out.push(cur)
      cur = []
      chars = 0
    }
    cur.push(u)
    chars += cost
  }
  if (cur.length) out.push(cur)
  return out
}

function writeIfChanged(path, content) {
  if (readFileSync(path, 'utf8') === content) return false
  const tmp = `${path}.tmp`
  writeFileSync(tmp, content, 'utf8')
  renameSync(tmp, path)
  return true
}

// ---- main -------------------------------------------------------------------

async function main() {
  const modules = opt.only ? MODULES.filter((m) => m.includes(opt.only)) : MODULES
  if (modules.length === 0) {
    console.error(`--only "${opt.only}" matched no module of: ${MODULES.join(', ')}`)
    process.exit(2)
  }

  const skipUnused = !opt.all
  const used = skipUnused ? usedL10nKeys() : null
  if (skipUnused) console.log(`app references ${used.size} l10n keys; skipping the rest (--all to include them)`)

  let idBase = 0
  const files = []
  let skipped = 0
  for (const m of modules) {
    const units = collectUnits(m, idBase, used)
    if (!units) {
      console.warn(`skip ${m}: missing source or ${LANG} file`)
      continue
    }
    if (skipUnused) skipped += units.skipped
    idBase += units.units.length
    files.push({ module: m, path: join(DEST_DIR, m, `${LANG}.xml`), units: units.units })
  }
  if (skipUnused) console.log(`skipped ${skipped} keys no screen reads`)

  const allUnits = files.flatMap((f) => f.units)
  const batches = chunk(allUnits)
  console.log(`${files.length} modules, ${allUnits.length} strings, ${batches.length} batches`)
  console.log(`model=${cfg.model} endpoint=${cfg.baseUrl}`)
  if (opt.dryRun) console.log('(dry run: nothing will be written)')

  const accepted = new Map()
  const rejected = []
  let done = 0

  for (const batch of batches) {
    if (opt.limit && done >= opt.limit) {
      console.log(`--limit ${opt.limit} reached, stopping early`)
      break
    }
    done++
    process.stdout.write(`[${done}/${batches.length}] ${batch.length} strings... `)
    let result
    try {
      result = await translateBatch(batch)
    } catch (e) {
      console.log(`FAILED (${e.message})`)
      continue
    }
    let ok = 0
    for (const u of batch) {
      const text = result.get(u.id)
      if (typeof text !== 'string') {
        rejected.push({ unit: u, why: 'missing from response' })
        continue
      }
      const why = reject(u, text)
      if (why) {
        rejected.push({ unit: u, why })
        continue
      }
      accepted.set(u.id, text)
      ok++
    }
    console.log(`${ok}/${batch.length} accepted`)
  }

  console.log(`\n${accepted.size} accepted, ${rejected.length} rejected`)
  if (rejected.length) {
    const byReason = new Map()
    for (const r of rejected) byReason.set(r.why, (byReason.get(r.why) ?? 0) + 1)
    for (const [why, n] of [...byReason].sort((a, b) => b[1] - a[1])) console.log(`  ${n}x ${why}`)
    console.log('  examples:')
    for (const r of rejected.slice(0, 5)) {
      console.log(`    ${r.unit.module}/${r.unit.name}: ${r.why}`)
    }
  }

  let written = 0
  let changedTotal = 0
  const rows = []
  for (const f of files) {
    const edits = []
    for (const u of f.units) {
      const text = accepted.get(u.id)
      if (text != null && text !== u.existing) edits.push({ name: u.name, quantity: u.quantity, text })
    }
    if (edits.length === 0) {
      rows.push([f.module, 0, f.units.length])
      continue
    }
    const raw = readFileSync(f.path, 'utf8')
    const { text, missed } = replaceValues(raw, edits)
    if (missed.length) {
      console.warn(`  ${f.module}: ${missed.length} edit(s) matched no element, skipped`)
    }
    changedTotal += edits.length
    rows.push([f.module, edits.length, f.units.length])
    if (opt.dryRun) continue
    if (writeIfChanged(f.path, text)) written++
  }

  console.log('\nmodule          changed / total')
  for (const [m, c, t] of rows) console.log(`  ${m.padEnd(14)} ${String(c).padStart(5)}  / ${String(t).padStart(5)}`)
  console.log(
    opt.dryRun
      ? `\ndry run: ${changedTotal} strings would change across ${rows.filter((r) => r[1] > 0).length} files`
      : `\nwrote ${written} file(s), ${changedTotal} string(s) changed`,
  )
  if (!opt.dryRun && written > 0) {
    console.log('\nNext: run ./scripts/gen-translations.sh (needs flutter), then review `git diff`.')
  }
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
