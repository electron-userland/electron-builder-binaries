import { isPng } from './png'
import { debug } from './log'

// Non-image entries that never carry pixel data.
const META_TYPES = new Set(['info', 'TOC ', 'icnV', 'name'])
// Legacy 8-bit alpha masks (paired with the raw 24-bit types below).
const MASK_TYPES = new Set(['s8mk', 'l8mk', 'h8mk', 't8mk'])
// Legacy raw (uncompressed / RLE 24-bit or indexed) image types.
const RAW_TYPES = new Set([
  'ICON', 'ICN#', 'icm#', 'icm4', 'icm8', 'ics#', 'ics4', 'ics8', 'is32',
  'icl4', 'icl8', 'il32', 'ich#', 'ich4', 'ich8', 'ih32', 'it32', 'icp4', 'icp5', 'icp6',
])

const ICNS_MAGIC = 'icns'
const JP2_BOX_MAGIC = Buffer.from([0x00, 0x00, 0x00, 0x0c, 0x6a, 0x50, 0x20, 0x20, 0x0d, 0x0a, 0x87, 0x0a])
const J2K_CODESTREAM_MAGIC = Buffer.from([0xff, 0x4f, 0xff, 0x51])
const ARGB_MAGIC = Buffer.from('ARGB', 'ascii')

export type IcnsEncoding = 'png' | 'jp2' | 'argb' | 'raw' | 'mask' | 'meta' | 'unknown'

export interface IcnsEntryInfo {
  ostype: string
  length: number
  encoding: IcnsEncoding
  width?: number
  height?: number
}

export interface IcnsExtractResult {
  // The largest PNG frame found in the container, or null if none is decodable.
  png: Buffer | null
  // Every parsed entry, for diagnostics when extraction fails.
  entries: IcnsEntryInfo[]
}

function startsWith(data: Buffer, magic: Buffer): boolean {
  return data.length >= magic.length && data.subarray(0, magic.length).equals(magic)
}

function classify(ostype: string, payload: Buffer): IcnsEncoding {
  if (isPng(payload)) return 'png'
  if (startsWith(payload, JP2_BOX_MAGIC) || startsWith(payload, J2K_CODESTREAM_MAGIC)) return 'jp2'
  if (startsWith(payload, ARGB_MAGIC)) return 'argb'
  if (META_TYPES.has(ostype)) return 'meta'
  if (MASK_TYPES.has(ostype)) return 'mask'
  if (RAW_TYPES.has(ostype)) return 'raw'
  return 'unknown'
}

// Parse the ICNS container into a flat list of entries with detected encodings,
// then return the largest PNG frame (by pixel width). Unlike a fixed OSType
// allow-list, this inspects EVERY image-bearing entry, so a valid .icns whose
// only/largest PNG lives in any type (icp4/icp5/icp6/ic07/ic08…/ic14) is found.
// Non-PNG encodings (JPEG 2000, ARGB, legacy raw) cannot be decoded by the
// bundled wasm-vips build and are reported via `entries` for diagnostics.
export function extractLargestPngFromIcns(data: Buffer): IcnsExtractResult {
  const entries: IcnsEntryInfo[] = []

  if (data.length < 8 || data.toString('ascii', 0, 4) !== ICNS_MAGIC) {
    debug('icns: not a valid ICNS container (bad magic)')
    return { png: null, entries }
  }

  let best: { png: Buffer; width: number } | null = null
  let offset = 8 // skip the 8-byte ICNS file header (magic + total length)
  while (offset + 8 <= data.length) {
    const ostype = data.toString('ascii', offset, offset + 4)
    const entryLen = data.readUInt32BE(offset + 4)
    if (entryLen < 8) {
      debug(`icns: stopping at offset ${offset}: invalid entry length ${entryLen}`)
      break
    }
    const payloadStart = offset + 8
    const payloadEnd = offset + entryLen
    if (payloadEnd > data.length) {
      debug(`icns: truncated entry "${ostype}" at offset ${offset} (declares ${entryLen} bytes, ${data.length - offset} remain)`)
      break
    }
    const payload = data.subarray(payloadStart, payloadEnd)
    const encoding = classify(ostype, payload)
    const info: IcnsEntryInfo = { ostype, length: payload.length, encoding }

    if (encoding === 'png' && payload.length >= 24) {
      info.width = payload.readUInt32BE(16)
      info.height = payload.readUInt32BE(20)
      if (best == null || info.width > best.width) {
        best = { png: payload, width: info.width }
      }
    }

    entries.push(info)
    offset += entryLen
  }

  debug(`icns: parsed ${entries.length} entries [${entries.map(e => `${e.ostype}:${e.encoding}${e.width ? `:${e.width}x${e.height}` : ''}`).join(', ')}]`)
  if (best != null) {
    debug(`icns: selected largest PNG frame (${best.width}px)`)
    return { png: best.png, entries }
  }
  debug('icns: no PNG frame found')
  return { png: null, entries }
}

// Human-readable summary of parsed entries, used in the CLI failure message.
export function describeIcnsEntries(entries: IcnsEntryInfo[]): string {
  if (entries.length === 0) return 'none'
  return entries
    .map(e => `${e.ostype}(${e.encoding}, ${e.length}B${e.width ? `, ${e.width}x${e.height}` : ''})`)
    .join(', ')
}
