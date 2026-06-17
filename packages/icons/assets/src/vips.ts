import { readFileSync } from 'fs'
import { join } from 'path'
import { retryOnAllocationFailure } from './retry'
import { debug } from './log'

// Load vips-node.js as a sidecar at runtime (NOT bundled by esbuild).
// When bundled, vips-node.js sets ha=__filename to the bundle path, causing workers to
// re-enter the bundle and deadlock. Loaded as a sidecar, ha=__filename points to
// vips-node.js itself, so workers spawn independently without touching the bundle.
// eslint-disable-next-line @typescript-eslint/no-var-requires
const VipsFactory = require(join(__dirname, 'vips-node.js'))

// Memoize the in-flight init PROMISE, not the resolved instance. createIco/createIcns
// kick off several resizeWithLanczos calls concurrently via Promise.all; if we keyed
// on the resolved value, every one of them would see a still-null instance and spin up
// its OWN VipsFactory — each committing a separate 1 GiB shared WebAssembly.Memory.
// Sharing the promise guarantees exactly one init (one allocation) per process. On
// failure we clear it so a later call can retry instead of being poisoned.
let vipsPromise: Promise<any> | null = null

function getVips(): Promise<any> {
  if (vipsPromise == null) {
    vipsPromise = initVips().catch(err => {
      vipsPromise = null
      throw err
    })
  }
  return vipsPromise
}

async function initVips(): Promise<any> {
  // Bypass the default Emscripten WASM loader (which fails inside esbuild bundles)
  // by pre-reading the WASM binary and using instantiateWasm directly — the same
  // pattern resvg-wasm uses for its init. Skip optional codecs (HEIF, JXL, resvg).
  const wasmBuffer = readFileSync(join(__dirname, 'vips.wasm'))
  debug('vips: initializing wasm-vips (1 GiB shared memory)')
  // wasm-vips commits a fixed 1 GiB shared WebAssembly.Memory on init. Under
  // concurrent invocations this can transiently exhaust the host's memory and
  // throw "could not allocate memory"; retry with backoff until peers free up.
  // See retry.ts for the full rationale.
  const vips = await retryOnAllocationFailure(() =>
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
  debug('vips: ready')
  return vips
}

// Resize an image buffer to exactly targetSize×targetSize using Lanczos3 resampling
// (vips thumbnail: box-filter pre-shrink + Lanczos final stage, matching the Go
// icon-converter's imaging.Lanczos). The aspect ratio is preserved: a non-square
// source is fitted inside the box and padded to a square with a transparent
// background rather than stretched. A square source needs no padding (fast path).
export async function resizeWithLanczos(imageBuffer: Buffer, targetSize: number): Promise<Buffer> {
  const vips = await getVips()
  let thumb: any = null
  let squared: any = null
  let padded: any = null
  try {
    // Size.both fits within targetSize×targetSize preserving aspect ratio. Callers
    // cap targetSize at the source's largest dimension, so this only downscales.
    thumb = vips.Image.thumbnailBuffer(imageBuffer, targetSize, {
      height: targetSize,
      size: vips.Size.both,
    })
    if (thumb.width === targetSize && thumb.height === targetSize) {
      return Buffer.from(thumb.writeToBuffer('.png'))
    }
    // Non-square: center on a transparent square canvas (ensure an alpha channel first).
    squared = thumb.hasAlpha() ? thumb : thumb.bandjoin(255)
    padded = squared.gravity('centre', targetSize, targetSize, {
      extend: 'background',
      background: [0, 0, 0, 0],
    })
    return Buffer.from(padded.writeToBuffer('.png'))
  } finally {
    if (padded) padded.delete()
    if (squared && squared !== thumb) squared.delete()
    if (thumb) thumb.delete()
  }
}
