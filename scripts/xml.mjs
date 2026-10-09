// Minimal, lossless XML handling for the Lichess translation files.
//
// These files have a very regular shape: a flat list of `<string name="…">` and
// `<plurals name="…"><item quantity="…">` elements. Parsing the whole document
// and re-serializing it would be simpler, but it would also reflow every file
// and bury a three-string change in a 900-line diff. So instead this module
// reads with a parser and writes with targeted range replacements: everything
// outside the changed text nodes survives byte-for-byte, including attribute
// order, indentation and the XML declaration.
//
// Text is decoded on read and encoded on write, so a caller only ever handles
// plain strings. Without that, a `&quot;` round-tripped through an LLM and back
// would double-escape into `&amp;quot;`.

const ELEMENT_RE = /<(string|plurals)\b([^>]*)>([\s\S]*?)<\/\1>/g
const ITEM_RE = /<item\b([^>]*)>([\s\S]*?)<\/item>/g
const ATTR_RE = /([A-Za-z_:][\w:.-]*)\s*=\s*"([^"]*)"/g

const ENTITIES = [
  ['&lt;', '<'],
  ['&gt;', '>'],
  ['&quot;', '"'],
  ['&apos;', "'"],
  ['&amp;', '&'], // must be last, or "&amp;lt;" would decode twice
]

export function decode(text) {
  let out = text
  for (const [entity, char] of ENTITIES) out = out.split(entity).join(char)
  return out.replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
}

// Only the three characters that would break the markup are escaped, and a real
// newline is written as the two-character `\n` escape. That is not arbitrary:
// these files write literal `"` in text (never `&quot;`), gen-arb's unescape()
// turns `\n` into a newline, and xml2js decodes `&#10;` into the same newline —
// so `\n` is both the dominant convention here and semantically identical.
export function encode(text) {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/\n/g, '\\n')
}

/** Counts line breaks, treating the `\n` escape and a real newline as the same
 * thing: files are inconsistent about which they use for the same value. */
export function lineBreaks(text) {
  return text.split(/\\n|\n/).length - 1
}

function attrsOf(raw) {
  const attrs = {}
  for (const [, name, value] of raw.matchAll(ATTR_RE)) attrs[name] = decode(value)
  return attrs
}

/**
 * @param {string} raw file contents
 * @returns {{ strings: Array<{name:string, attrs:object, text:string}>,
 *             plurals: Array<{name:string, attrs:object, items:Array<{quantity:string, text:string}>}> }}
 *   `text` values are decoded; `raw` offsets are not exposed.
 */
export function parseXml(raw) {
  const strings = []
  const plurals = []
  for (const [, tag, attrRaw, body] of raw.matchAll(ELEMENT_RE)) {
    const attrs = attrsOf(attrRaw)
    if (tag === 'string') {
      strings.push({ name: attrs.name, attrs, text: decode(body) })
    } else {
      const items = []
      for (const [, itemAttrRaw, itemBody] of body.matchAll(ITEM_RE)) {
        items.push({ quantity: attrsOf(itemAttrRaw).quantity, text: decode(itemBody) })
      }
      plurals.push({ name: attrs.name, attrs, items })
    }
  }
  return { strings, plurals }
}

/**
 * Rewrites the text content of the named elements, leaving markup untouched.
 *
 * @param {string} raw
 * @param {Array<{name:string, quantity?:string, text:string}>} edits
 *   `quantity` selects one `<item>` inside a `<plurals>`; omit it for a `<string>`.
 * @returns {{ text:string, applied:number, missed:Array<object> }}
 */
export function replaceValues(raw, edits) {
  // Locate every editable text node once, then serve all edits from that index.
  // Offsets are collected first and spliced in reverse so earlier replacements
  // cannot invalidate later ones.
  const nodes = []
  for (const match of raw.matchAll(ELEMENT_RE)) {
    const tag = match[1]
    const attrs = attrsOf(match[2])
    const body = match[3]
    const bodyStart = match.index + match[0].length - body.length - `</${tag}>`.length
    if (tag === 'string') {
      nodes.push({
        name: attrs.name,
        quantity: null,
        text: decode(body),
        start: bodyStart,
        end: bodyStart + body.length,
      })
    } else {
      for (const item of body.matchAll(ITEM_RE)) {
        const itemBody = item[2]
        const start = bodyStart + item.index + item[0].length - itemBody.length - '</item>'.length
        nodes.push({
          name: attrs.name,
          quantity: attrsOf(item[1]).quantity,
          text: decode(itemBody),
          start,
          end: start + itemBody.length,
        })
      }
    }
  }

  const index = new Map()
  for (const node of nodes) {
    index.set(`${node.name}\u0000${node.quantity ?? ''}`, node)
  }

  const applied = []
  const missed = []
  for (const edit of edits) {
    const node = index.get(`${edit.name}\u0000${edit.quantity ?? ''}`)
    if (!node) {
      missed.push(edit)
      continue
    }
    // An unchanged value keeps its original bytes verbatim. Re-encoding would be
    // semantically identical but not byte-identical — the files disagree on
    // `"` vs `&quot;` and on real newlines vs `&#10;` — and those cosmetic
    // rewrites would show up in the diff as changes nobody made.
    if (node.text === edit.text) continue
    applied.push({ start: node.start, end: node.end, replacement: encode(edit.text) })
  }

  applied.sort((a, b) => b.start - a.start)
  let out = raw
  for (const a of applied) out = out.slice(0, a.start) + a.replacement + out.slice(a.end)
  return { text: out, applied: applied.length, missed }
}

/**
 * The set of printf-ish placeholders a string uses.
 *
 * Order is deliberately discarded: `%1$s`/`%2$s` exist so a translator can move
 * a value to the position the target language wants, so a reordering is correct
 * while a dropped or duplicated placeholder is a runtime format crash.
 */
export function placeholders(text) {
  return [...text.matchAll(/%%|%\d+\$[sd]|%[sd]/g)].map((m) => m[0]).sort()
}

export function samePlaceholders(a, b) {
  const pa = placeholders(a)
  const pb = placeholders(b)
  return pa.length === pb.length && pa.every((v, i) => v === pb[i])
}
