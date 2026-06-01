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
