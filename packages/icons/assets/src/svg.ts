import { readFileSync } from 'fs'
import { join } from 'path'

// @resvg/resvg-wasm is bundled as CJS; its JS bindings are inlined by esbuild.
// The wasm binary is NOT bundled — it lives at __dirname/resvg.wasm and is loaded
// at runtime via readFileSync so no fetch() is needed (Node 14 compat).
// eslint-disable-next-line @typescript-eslint/no-var-requires
const resvgWasm = require('@resvg/resvg-wasm')

let initialized = false

async function ensureInit(): Promise<void> {
  if (initialized) return
  const wasmPath = join(__dirname, 'resvg.wasm')
  const wasmBuffer = readFileSync(wasmPath)
  await resvgWasm.initWasm(wasmBuffer)
  initialized = true
}

export async function svgToPng(svgData: Buffer, targetWidth: number): Promise<Buffer> {
  await ensureInit()
  const resvg = new resvgWasm.Resvg(svgData, {
    fitTo: { mode: 'width', value: targetWidth },
  })
  const rendered = resvg.render()
  return Buffer.from(rendered.asPng())
}

// Resize a PNG buffer to targetWidth×targetWidth using resvg-wasm.
// Wraps the PNG in an SVG <image> element — the same high-quality resampling
// path that createLinuxSet uses — so no additional dependencies are needed.
export async function resizePng(pngBuffer: Buffer, targetWidth: number): Promise<Buffer> {
  const b64 = pngBuffer.toString('base64')
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${targetWidth}" height="${targetWidth}"><image href="data:image/png;base64,${b64}" width="${targetWidth}" height="${targetWidth}"/></svg>`
  return svgToPng(Buffer.from(svg), targetWidth)
}
