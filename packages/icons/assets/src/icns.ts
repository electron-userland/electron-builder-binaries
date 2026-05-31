import { writeFileSync } from 'fs'
import { join } from 'path'
import * as png2icons from 'png2icons'

export function createIcns(inputBuffer: Buffer, outputDir: string): void {
  const icnsBuffer = png2icons.createICNS(inputBuffer, png2icons.BILINEAR, 0)
  if (!icnsBuffer) throw new Error('png2icons failed to create ICNS — ensure input is a valid PNG (1024×1024 recommended)')
  writeFileSync(join(outputDir, 'icon.icns'), icnsBuffer)
}
