import { writeFileSync } from 'fs'
import { join } from 'path'
import { resizeWithLanczos } from './vips'

const ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]

// Pack pre-sized PNG frames into a Vista+ ICO container.
// PNG frames are embedded directly (valid from Windows Vista onward);
// byte value 0 in the directory width/height field encodes 256.
function packIco(frames: Array<{ size: number; png: Buffer }>): Buffer {
  const count = frames.length
  let offset = 6 + count * 16

  const header = Buffer.allocUnsafe(6)
  header.writeUInt16LE(0, 0)
  header.writeUInt16LE(1, 2)
  header.writeUInt16LE(count, 4)

  const dir = frames.map(({ size, png }) => {
    const entry = Buffer.allocUnsafe(16)
    const w = size === 256 ? 0 : size
    entry.writeUInt8(w, 0)
    entry.writeUInt8(w, 1)
    entry.writeUInt8(0, 2)        // color count (0 = true-color)
    entry.writeUInt8(0, 3)        // reserved
    entry.writeUInt16LE(1, 4)     // planes
    entry.writeUInt16LE(32, 6)    // bits per pixel
    entry.writeUInt32LE(png.length, 8)
    entry.writeUInt32LE(offset, 12)
    offset += png.length
    return entry
  })

  return Buffer.concat([header, ...dir, ...frames.map(f => f.png)])
}

export async function createIco(inputBuffer: Buffer, outputDir: string): Promise<void> {
  const frames = await Promise.all(
    ICO_SIZES.map(async size => ({ size, png: await resizeWithLanczos(inputBuffer, size) }))
  )
  writeFileSync(join(outputDir, 'icon.ico'), packIco(frames))
}
