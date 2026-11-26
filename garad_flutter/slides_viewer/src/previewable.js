// The same preview fixes as garad.ai (frontend/src/core/pptxPreview.ts): the renderer does not decode
// numeric character references such as char="&#x2022;", which pptxgenjs writes for every bullet (Claude's
// decks showed "&#x2022;" before each bullet), and it printed a notes page's slide-number field after
// the speaker notes. Only the preview reads the fixed copy; the file the user shares is untouched.

import { strFromU8, strToU8, unzipSync, zipSync } from "fflate"

// Characters that must stay escaped in XML (", &, ', <, >), and control characters.
const KEEP = new Set([0x22, 0x26, 0x27, 0x3c, 0x3e])

export function decodeCharacterReferences(xml) {
  return xml.replace(/&#(x[0-9a-fA-F]+|[0-9]+);/g, (reference, code) => {
    const point = code.startsWith("x") ? parseInt(code.slice(1), 16) : parseInt(code, 10)
    if (!Number.isFinite(point) || point < 0x20 || point > 0x10ffff || KEEP.has(point)) return reference
    return String.fromCodePoint(point)
  })
}

const NOTES_SLIDE_NUMBER = /<p:sp>(?:(?!<\/p:sp>)[\s\S])*?<p:ph type="sldNum"[\s\S]*?<\/p:sp>/g

/** The deck as the preview should read it; the original bytes when nothing changes or it can't be read. */
export function previewablePptx(bytes) {
  try {
    const files = unzipSync(bytes)
    let changed = false
    for (const [path, data] of Object.entries(files)) {
      if (!/^ppt\/.+\.xml$/i.test(path)) continue
      const xml = strFromU8(data)
      let fixed = xml.includes("&#") ? decodeCharacterReferences(xml) : xml
      if (/^ppt\/notesSlides\//i.test(path)) fixed = fixed.replace(NOTES_SLIDE_NUMBER, "")
      if (fixed !== xml) {
        files[path] = strToU8(fixed)
        changed = true
      }
    }
    return changed ? zipSync(files) : bytes
  } catch {
    return bytes
  }
}
