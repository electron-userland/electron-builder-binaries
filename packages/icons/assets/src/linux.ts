import { writeFileSync } from 'fs'
import { join } from 'path'
import { resizeWithLanczos } from './vips'
import { readPngSize } from './png'

const LINUX_SIZES = [16, 24, 32, 48, 64, 128, 256, 512]

export async function createLinuxSet(inputBuffer: Buffer, outputDir: string): Promise<void> {
  // Never upscale: only emit sizes the source can supply (fall back to the source's
  // own size if it is smaller than the smallest standard size).
  const { width, height } = readPngSize(inputBuffer)
  const sourceSize = Math.max(width, height)
  const sizes = LINUX_SIZES.filter(s => s <= sourceSize)
  if (sizes.length === 0) {
    sizes.push(sourceSize)
  }
  for (const size of sizes) {
    const resized = await resizeWithLanczos(inputBuffer, size)
    writeFileSync(join(outputDir, `${size}x${size}.png`), resized)
  }
}
