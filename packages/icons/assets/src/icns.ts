import { writeFileSync } from 'fs'
import { join } from 'path'
import { resizeWithLanczos, resizeToRawRgba } from './vips'
import { encodeArgb } from './argb'
import { readPngSize } from './png'

// Standard macOS ICNS entries, mirroring exactly what Apple's `iconutil` emits at each
// render size — the representation macOS is guaranteed to render correctly.
//
// The 16px and 32px 1× icons use the ic04/ic05 OSTypes in ARGB form (see argb.ts). They are
// NOT stored as PNG: although the icp4/icp5/icp6 chunks can technically carry a PNG, macOS
// does not render those correctly and the small icons appeared corrupt in Finder's
// list/column/Trash views (electron-userland/electron-builder#9980, #9940). Every larger size
// is a PNG. HiDPI entries (ic11–ic14) carry the same pixel data as their standard
// counterparts — same render dimensions, different logical resolution label.
const ICNS_ENTRIES: Array<{ osType: string; size: number; encoding: 'png' | 'argb' }> = [
  { osType: 'ic04', size: 16, encoding: 'argb' },   // icon_16x16.png
  { osType: 'ic05', size: 32, encoding: 'argb' },   // icon_32x32.png
  { osType: 'ic07', size: 128, encoding: 'png' },   // icon_128x128.png
  { osType: 'ic08', size: 256, encoding: 'png' },   // icon_256x256.png
  { osType: 'ic09', size: 512, encoding: 'png' },   // icon_512x512.png
  { osType: 'ic10', size: 1024, encoding: 'png' },  // icon_512x512@2x.png
  { osType: 'ic11', size: 32, encoding: 'png' },    // icon_16x16@2x.png
  { osType: 'ic12', size: 64, encoding: 'png' },    // icon_32x32@2x.png
  { osType: 'ic13', size: 256, encoding: 'png' },   // icon_128x128@2x.png
  { osType: 'ic14', size: 512, encoding: 'png' },   // icon_256x256@2x.png
]

// Pack pre-encoded frames into an ICNS container.
function packIcns(frames: Array<{ osType: string; payload: Buffer }>): Buffer {
  const chunks = frames.flatMap(({ osType, payload }) => {
    const hdr = Buffer.allocUnsafe(8)
    Buffer.from(osType, 'ascii').copy(hdr, 0)
    hdr.writeUInt32BE(8 + payload.length, 4)
    return [hdr, payload]
  })
  const body = Buffer.concat(chunks)
  const fileHeader = Buffer.allocUnsafe(8)
  Buffer.from('icns', 'ascii').copy(fileHeader, 0)
  fileHeader.writeUInt32BE(8 + body.length, 4)
  return Buffer.concat([fileHeader, body])
}

export async function createIcns(inputBuffer: Buffer, outputDir: string): Promise<void> {
  // Determine source size from the PNG IHDR chunk to avoid upscaling. readPngSize
  // validates the signature/IHDR so a non-PNG input fails loudly instead of being
  // mis-sized from arbitrary bytes at offset 16.
  const { width, height } = readPngSize(inputBuffer)
  const sourceSize = Math.max(width, height)

  const entries = ICNS_ENTRIES.filter(e => e.size <= sourceSize)
  if (entries.length === 0) {
    throw new Error(`Source image is too small to build an ICNS (need at least 16px, got ${sourceSize}px)`)
  }

  // Generate each unique (encoding, size) payload once; HiDPI duplicates reuse the buffer.
  // Note size 32 is produced both as ARGB (ic05) and PNG (ic11), so the two encodings are
  // keyed independently.
  const pngSizes = [...new Set(entries.filter(e => e.encoding === 'png').map(e => e.size))]
  const argbSizes = [...new Set(entries.filter(e => e.encoding === 'argb').map(e => e.size))]
  const pngBySize = new Map<number, Buffer>()
  const argbBySize = new Map<number, Buffer>()
  await Promise.all([
    ...pngSizes.map(async size => {
      pngBySize.set(size, await resizeWithLanczos(inputBuffer, size))
    }),
    ...argbSizes.map(async size => {
      argbBySize.set(size, encodeArgb(await resizeToRawRgba(inputBuffer, size), size))
    }),
  ])

  const frames = entries.map(({ osType, size, encoding }) => ({
    osType,
    payload: encoding === 'argb' ? argbBySize.get(size)! : pngBySize.get(size)!,
  }))
  writeFileSync(join(outputDir, 'icon.icns'), packIcns(frames))
}
