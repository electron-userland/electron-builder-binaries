import { writeFileSync } from 'fs'
import { join } from 'path'
import { svgToPng } from './svg'

const LINUX_SIZES = [16, 24, 32, 48, 64, 128, 256, 512]

// Resize by wrapping the PNG in an SVG image element and rendering via resvg-wasm.
// This reuses the wasm already bundled for SVG support — no extra dependencies.
export async function createLinuxSet(inputBuffer: Buffer, outputDir: string): Promise<void> {
  const b64 = inputBuffer.toString('base64')
  for (const size of LINUX_SIZES) {
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${size}" height="${size}"><image href="data:image/png;base64,${b64}" width="${size}" height="${size}"/></svg>`
    const resized = await svgToPng(Buffer.from(svg), size)
    writeFileSync(join(outputDir, `${size}x${size}.png`), resized)
  }
}
