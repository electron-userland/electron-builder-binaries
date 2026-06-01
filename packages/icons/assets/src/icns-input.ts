// ICNS types in priority order: largest frames first.
const PREFERRED_TYPES = ['ic10', 'ic09', 'ic14', 'ic08', 'ic13']
const SKIP_TYPES = new Set(['info', 'TOC ', 'icnV', 'name'])

export function extractLargestPngFromIcns(data: Buffer): Buffer | null {
  const typeMap = new Map<string, { offset: number; length: number }>()
  let offset = 8 // skip 8-byte ICNS file header
  while (offset < data.length) {
    if (offset + 8 > data.length) break
    const ostype = data.toString('ascii', offset, offset + 4)
    const entryLen = data.readUInt32BE(offset + 4)
    if (entryLen < 8) break
    if (!SKIP_TYPES.has(ostype)) {
      typeMap.set(ostype, { offset: offset + 8, length: entryLen - 8 })
    }
    offset += entryLen
  }
  for (const t of PREFERRED_TYPES) {
    const entry = typeMap.get(t)
    if (entry) return data.subarray(entry.offset, entry.offset + entry.length)
  }
  return null
}
