import { writeFileSync } from 'fs'
import { join } from 'path'
import { resizeWithLanczos } from './vips'
import { readPngSize } from './png'

// Standard macOS ICNS entries. HiDPI entries (ic11–ic14) carry the same pixel
// data as their standard counterparts — same render dimensions, different logical
// resolution label. Both are required by macOS for correct HiDPI display.
const ICNS_ENTRIES: Array<{ osType: string; size: number }> = [
  { osType: 'icp4', size: 16 },
  { osType: 'icp5', size: 32 },
  { osType: 'icp6', size: 64 },
  { osType: 'ic07', size: 128 },
  { osType: 'ic08', size: 256 },
  { osType: 'ic09', size: 512 },
  { osType: 'ic10', size: 1024 },
  { osType: 'ic11', size: 32 },    // 16@2x
  { osType: 'ic12', size: 64 },    // 32@2x
  { osType: 'ic13', size: 256 },   // 128@2x
  { osType: 'ic14', size: 512 },   // 256@2x
]

// Pack pre-sized PNG frames into an ICNS container.
function packIcns(frames: Array<{ osType: string; png: Buffer }>): Buffer {
  const chunks = frames.flatMap(({ osType, png }) => {
    const hdr = Buffer.allocUnsafe(8)
    Buffer.from(osType, 'ascii').copy(hdr, 0)
    hdr.writeUInt32BE(8 + png.length, 4)
    return [hdr, png]
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

  // Generate each unique pixel size once, reuse for HiDPI duplicates
  const uniqueSizes = [...new Set(entries.map(e => e.size))]
  const pngBySize = new Map<number, Buffer>()
  await Promise.all(
    uniqueSizes.map(async size => {
      pngBySize.set(size, await resizeWithLanczos(inputBuffer, size))
    })
  )

  const frames = entries.map(({ osType, size }) => ({ osType, png: pngBySize.get(size)! }))
  writeFileSync(join(outputDir, 'icon.icns'), packIcns(frames))
}
