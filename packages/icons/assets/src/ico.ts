import { writeFileSync } from 'fs'
import { join } from 'path'
import * as png2icons from 'png2icons'
import { resizePng } from './svg'

// ICO directory entries store width/height as a single byte (0 = 256), so 256×256
// is the maximum frame size. Pre-resizing to exactly 256×256 via resvg-wasm
// (high-quality resampling) gives png2icons a clean source for generating the
// smaller sizes (16, 32, 48, …), matching the Go icon-converter's Lanczos approach.
const ICO_MAX_SIZE = 256

export async function createIco(inputBuffer: Buffer, outputDir: string): Promise<void> {
  const resized = await resizePng(inputBuffer, ICO_MAX_SIZE)
  const icoBuffer = png2icons.createICO(resized, png2icons.BEZIER, 0, false)
  if (!icoBuffer) throw new Error('png2icons failed to create ICO — ensure input is a valid PNG (256×256 or larger recommended)')
  writeFileSync(join(outputDir, 'icon.ico'), icoBuffer)
}
