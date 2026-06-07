import { writeFileSync } from 'fs'
import { join } from 'path'
import { resizeWithLanczos } from './vips'

const LINUX_SIZES = [16, 24, 32, 48, 64, 128, 256, 512]

export async function createLinuxSet(inputBuffer: Buffer, outputDir: string): Promise<void> {
  for (const size of LINUX_SIZES) {
    const resized = await resizeWithLanczos(inputBuffer, size)
    writeFileSync(join(outputDir, `${size}x${size}.png`), resized)
  }
}
