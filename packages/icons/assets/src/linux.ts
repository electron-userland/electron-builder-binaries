import { writeFileSync } from 'fs'
import { join } from 'path'
import * as png2icons from 'png2icons'

const LINUX_SIZES = [16, 24, 32, 48, 64, 128, 256, 512]

export function createLinuxSet(inputBuffer: Buffer, outputDir: string): void {
  for (const size of LINUX_SIZES) {
    const resized = png2icons.createPNG(inputBuffer, png2icons.BILINEAR, size)
    if (!resized) throw new Error(`png2icons failed to create ${size}x${size} PNG`)
    writeFileSync(join(outputDir, `${size}x${size}.png`), resized)
  }
}
