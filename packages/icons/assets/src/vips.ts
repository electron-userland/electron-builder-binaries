import { readFileSync } from 'fs'
import { join } from 'path'
import { retryOnAllocationFailure } from './retry'

// Load vips-node.js as a sidecar at runtime (NOT bundled by esbuild).
// When bundled, vips-node.js sets ha=__filename to the bundle path, causing workers to
// re-enter the bundle and deadlock. Loaded as a sidecar, ha=__filename points to
// vips-node.js itself, so workers spawn independently without touching the bundle.
// eslint-disable-next-line @typescript-eslint/no-var-requires
const VipsFactory = require(join(__dirname, 'vips-node.js'))

let vipsInstance: any = null

async function getVips(): Promise<any> {
  if (vipsInstance) return vipsInstance
  // Bypass the default Emscripten WASM loader (which fails inside esbuild bundles)
  // by pre-reading the WASM binary and using instantiateWasm directly — the same
  // pattern resvg-wasm uses for its init. Skip optional codecs (HEIF, JXL, resvg).
  const wasmBuffer = readFileSync(join(__dirname, 'vips.wasm'))
  // wasm-vips commits a fixed 1 GiB shared WebAssembly.Memory on init. Under
  // concurrent invocations this can transiently exhaust the host's memory and
  // throw "could not allocate memory"; retry with backoff until peers free up.
  // See retry.ts for the full rationale.
  vipsInstance = await retryOnAllocationFailure(() =>
    VipsFactory({
      dynamicLibraries: [],
      instantiateWasm: (
        imports: WebAssembly.Imports,
        receiveInstance: (inst: WebAssembly.Instance, mod: WebAssembly.Module) => void
      ) => {
        WebAssembly.instantiate(wasmBuffer, imports).then(result => {
          receiveInstance(result.instance, result.module)
        })
        return {}
      },
    })
  )
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
