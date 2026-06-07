import { join } from 'path'

// eslint-disable-next-line @typescript-eslint/no-var-requires
const VipsFactory = require('wasm-vips')

let vipsInstance: any = null

async function getVips(): Promise<any> {
  if (vipsInstance) return vipsInstance
  vipsInstance = await VipsFactory({
    // Skip optional codecs (HEIF, JXL, resvg) — only PNG resize is needed
    dynamicLibraries: [],
    // Redirect WASM loading to our bundled vips.wasm next to icon-tool.js
    locateFile: (url: string) => join(__dirname, url),
  })
  return vipsInstance
}

// Resize a PNG buffer to exactly targetSize×targetSize using Lanczos3 resampling.
// Uses vips thumbnail algorithm: box-filter pre-shrink + Lanczos final stage,
// matching the quality approach of the Go icon-converter's imaging.Lanczos.
export async function resizeWithLanczos(pngBuffer: Buffer, targetSize: number): Promise<Buffer> {
  const vips = await getVips()
  const out = vips.Image.thumbnailBuffer(pngBuffer, targetSize, {
    height: targetSize,
    size: vips.Size.force,
  })
  const result = Buffer.from(out.writeToBuffer('.png'))
  out.delete()
  return result
}
