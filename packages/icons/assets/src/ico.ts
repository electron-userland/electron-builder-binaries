import { writeFileSync } from 'fs'
import { join } from 'path'
import * as png2icons from 'png2icons'

export function createIco(inputBuffer: Buffer, outputDir: string): void {
  const icoBuffer = png2icons.createICO(inputBuffer, png2icons.BILINEAR, 0, false)
  if (!icoBuffer) throw new Error('png2icons failed to create ICO — ensure input is a valid PNG (512×512 or larger recommended)')
  writeFileSync(join(outputDir, 'icon.ico'), icoBuffer)
}
