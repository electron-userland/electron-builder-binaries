import { execSync } from 'child_process'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'fs'
import { deflateSync } from 'zlib'
import { join, dirname } from 'path'
import { tmpdir } from 'os'
import { parseIcns, parseIco, parsePngDimensions } from './validate'
import { isMemoryAllocationError, retryOnAllocationFailure } from '../src/retry'
import { parseArgs } from '../src/args'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Minimal CRC-32 used by PNG chunk writer below.
const CRC_TABLE: number[] = []
for (let i = 0; i < 256; i++) {
  let c = i
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
  CRC_TABLE[i] = c >>> 0
}
function crc32(buf: Buffer): number {
  let crc = 0xffffffff
  for (let i = 0; i < buf.length; i++) crc = CRC_TABLE[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8)
  return (crc ^ 0xffffffff) >>> 0
}

function pngChunk(type: string, data: Buffer): Buffer {
  const typeBytes = Buffer.from(type, 'ascii')
  const crcInput = Buffer.concat([typeBytes, data])
  const out = Buffer.allocUnsafe(4 + 4 + data.length + 4)
  out.writeUInt32BE(data.length, 0)
  typeBytes.copy(out, 4)
  data.copy(out, 8)
  out.writeUInt32BE(crc32(crcInput), 8 + data.length)
  return out
}

// Creates a valid solid-color PNG of the given size (pure Node.js, no deps).
function makeSolidPng(size: number, r = 70, g = 130, b = 220): Buffer {
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])

  const ihdr = Buffer.allocUnsafe(13)
  ihdr.writeUInt32BE(size, 0)
  ihdr.writeUInt32BE(size, 4)
  ihdr.writeUInt8(8, 8)   // bit depth
  ihdr.writeUInt8(2, 9)   // color type: RGB
  ihdr.writeUInt8(0, 10)  // compression
  ihdr.writeUInt8(0, 11)  // filter
  ihdr.writeUInt8(0, 12)  // interlace

  // Raw image data: one filter byte (None=0) + RGB pixels per scanline
  const rowLen = 1 + size * 3
  const raw = Buffer.allocUnsafe(size * rowLen)
  for (let y = 0; y < size; y++) {
    raw[y * rowLen] = 0
    for (let x = 0; x < size; x++) {
      raw[y * rowLen + 1 + x * 3] = r
      raw[y * rowLen + 1 + x * 3 + 1] = g
      raw[y * rowLen + 1 + x * 3 + 2] = b
    }
  }

  return Buffer.concat([
    sig,
    pngChunk('IHDR', ihdr),
    pngChunk('IDAT', deflateSync(raw)),
    pngChunk('IEND', Buffer.alloc(0)),
  ])
}

const TEST_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100">
  <rect width="100" height="100" fill="#4682dc"/>
  <circle cx="50" cy="50" r="35" fill="#ffffff" opacity="0.8"/>
</svg>`

// ---------------------------------------------------------------------------
// Test runner
// ---------------------------------------------------------------------------

type Test = {
  name: string
  run: (tmpDir: string, toolPath: string, pngFixture: string, svgFixture: string) => void | Promise<void>
}

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message)
}

const tests: Test[] = []

// Test 1: PNG → ICNS
tests.push({
  name: 'PNG → ICNS',
  run(tmpDir, toolPath, pngFixture) {
    const out = join(tmpDir, 'png-icns')
    mkdirSync(out)
    execSync(`node "${toolPath}" --input "${pngFixture}" --format icns --out "${out}"`)
    const file = join(out, 'icon.icns')
    if (!existsSync(file)) throw new Error('icon.icns was not created')
    const entries = parseIcns(readFileSync(file))
    if (entries.length === 0) throw new Error('ICNS file contains no entries')
    // At minimum, modern entries ic07–ic14 should be present for a 1024×1024 input
    const required = ['ic07', 'ic08', 'ic09', 'ic10']
    for (const e of required) {
      if (!entries.includes(e)) throw new Error(`ICNS is missing entry "${e}" (found: ${entries.join(', ')})`)
    }
  },
})

// Test 2: PNG → ICO
tests.push({
  name: 'PNG → ICO',
  run(tmpDir, toolPath, pngFixture) {
    const out = join(tmpDir, 'png-ico')
    mkdirSync(out)
    execSync(`node "${toolPath}" --input "${pngFixture}" --format ico --out "${out}"`)
    const file = join(out, 'icon.ico')
    if (!existsSync(file)) throw new Error('icon.ico was not created')
    const sizes = parseIco(readFileSync(file))
    if (sizes.length === 0) throw new Error('ICO file contains no images')
    const required = [16, 32, 48, 256]
    for (const s of required) {
      if (!sizes.includes(s)) throw new Error(`ICO is missing size ${s}px (found: ${sizes.join(', ')})`)
    }
  },
})

// Test 3: PNG → Linux PNG set
tests.push({
  name: 'PNG → Linux set',
  run(tmpDir, toolPath, pngFixture) {
    const out = join(tmpDir, 'png-set')
    mkdirSync(out)
    execSync(`node "${toolPath}" --input "${pngFixture}" --format set --out "${out}"`)
    const expectedSizes = [16, 24, 32, 48, 64, 128, 256, 512]
    for (const sz of expectedSizes) {
      const file = join(out, `${sz}x${sz}.png`)
      if (!existsSync(file)) throw new Error(`Missing ${sz}x${sz}.png`)
      const dims = parsePngDimensions(readFileSync(file))
      if (dims.width !== sz || dims.height !== sz) {
        throw new Error(`Wrong dimensions for ${sz}x${sz}.png: got ${dims.width}x${dims.height}`)
      }
    }
  },
})

// Test 4: SVG → ICNS (tests SVG rasterization path)
tests.push({
  name: 'SVG → ICNS',
  run(tmpDir, toolPath, _pngFixture, svgFixture) {
    const out = join(tmpDir, 'svg-icns')
    mkdirSync(out)
    execSync(`node "${toolPath}" --input "${svgFixture}" --format icns --out "${out}"`)
    const file = join(out, 'icon.icns')
    if (!existsSync(file)) throw new Error('icon.icns from SVG was not created')
    const entries = parseIcns(readFileSync(file))
    if (entries.length === 0) throw new Error('ICNS from SVG contains no entries')
  },
})

// Test 5: SVG → ICO
tests.push({
  name: 'SVG → ICO',
  run(tmpDir, toolPath, _pngFixture, svgFixture) {
    const out = join(tmpDir, 'svg-ico')
    mkdirSync(out)
    execSync(`node "${toolPath}" --input "${svgFixture}" --format ico --out "${out}"`)
    const file = join(out, 'icon.ico')
    if (!existsSync(file)) throw new Error('icon.ico from SVG was not created')
    const sizes = parseIco(readFileSync(file))
    if (!sizes.includes(256)) throw new Error(`ICO from SVG is missing 256px entry (found: ${sizes.join(', ')})`)
  },
})

// Test 6: ICNS → ICO (exercises the .icns input path + extractLargestPngFromIcns)
tests.push({
  name: 'ICNS → ICO',
  run(tmpDir, toolPath, pngFixture) {
    const step1 = join(tmpDir, 'icns-ico-step1')
    mkdirSync(step1)
    execSync(`node "${toolPath}" --input "${pngFixture}" --format icns --out "${step1}"`)
    const icnsFile = join(step1, 'icon.icns')
    if (!existsSync(icnsFile)) throw new Error('Step 1: icon.icns was not created')

    const step2 = join(tmpDir, 'icns-ico-step2')
    mkdirSync(step2)
    execSync(`node "${toolPath}" --input "${icnsFile}" --format ico --out "${step2}"`)
    const icoFile = join(step2, 'icon.ico')
    if (!existsSync(icoFile)) throw new Error('icon.ico from ICNS was not created')
    const sizes = parseIco(readFileSync(icoFile))
    if (!sizes.includes(256)) throw new Error(`ICO from ICNS is missing 256px entry (found: ${sizes.join(', ')})`)
  },
})

// Test 7: ICNS → Linux set (exercises the .icns input path + linux set generation)
tests.push({
  name: 'ICNS → Linux set',
  run(tmpDir, toolPath, pngFixture) {
    const step1 = join(tmpDir, 'icns-set-step1')
    mkdirSync(step1)
    execSync(`node "${toolPath}" --input "${pngFixture}" --format icns --out "${step1}"`)
    const icnsFile = join(step1, 'icon.icns')
    if (!existsSync(icnsFile)) throw new Error('Step 1: icon.icns was not created')

    const step2 = join(tmpDir, 'icns-set-step2')
    mkdirSync(step2)
    execSync(`node "${toolPath}" --input "${icnsFile}" --format set --out "${step2}"`)
    const expectedSizes = [16, 24, 32, 48, 64, 128, 256, 512]
    for (const sz of expectedSizes) {
      const file = join(step2, `${sz}x${sz}.png`)
      if (!existsSync(file)) throw new Error(`Missing ${sz}x${sz}.png`)
      const dims = parsePngDimensions(readFileSync(file))
      if (dims.width !== sz || dims.height !== sz) {
        throw new Error(`Wrong dimensions for ${sz}x${sz}.png: got ${dims.width}x${dims.height}`)
      }
    }
  },
})

// ---------------------------------------------------------------------------
// Unit tests: WASM memory-allocation retry (retry.ts)
// ---------------------------------------------------------------------------

// Deterministic options: no real timers, fixed RNG → tests run instantly.
const noWaitOpts = { sleep: async () => {}, random: () => 0 }

// Test 8: retries a transient memory-allocation failure then succeeds
tests.push({
  name: 'retry: recovers from transient allocation failure',
  async run() {
    let calls = 0
    const result = await retryOnAllocationFailure(async () => {
      calls++
      if (calls < 3) throw new Error('WebAssembly.Memory(): could not allocate memory')
      return 'ok'
    }, noWaitOpts)
    assert(result === 'ok', `expected "ok", got "${result}"`)
    assert(calls === 3, `expected 3 attempts, got ${calls}`)
  },
})

// Test 9: gives up after the configured attempts, surfacing the last error
tests.push({
  name: 'retry: gives up after exhausting attempts',
  async run() {
    let calls = 0
    let threw = false
    try {
      await retryOnAllocationFailure(async () => {
        calls++
        throw new Error('out of memory')
      }, { ...noWaitOpts, attempts: 4 })
    } catch (err) {
      threw = true
      assert(isMemoryAllocationError(err), 'expected a memory-allocation error to propagate')
    }
    assert(threw, 'expected retryOnAllocationFailure to throw after exhausting attempts')
    assert(calls === 4, `expected 4 attempts, got ${calls}`)
  },
})

// Test 10: does NOT retry non-allocation errors — they propagate immediately
tests.push({
  name: 'retry: rethrows non-allocation errors without retrying',
  async run() {
    let calls = 0
    let threw = false
    try {
      await retryOnAllocationFailure(async () => {
        calls++
        throw new Error('some unrelated bug')
      }, noWaitOpts)
    } catch (err) {
      threw = true
      assert((err as Error).message === 'some unrelated bug', 'expected the original error to propagate')
    }
    assert(threw, 'expected the non-allocation error to be thrown')
    assert(calls === 1, `expected exactly 1 attempt for a non-allocation error, got ${calls}`)
  },
})

// Test 11: isMemoryAllocationError classifies messages correctly
tests.push({
  name: 'retry: isMemoryAllocationError classification',
  run() {
    assert(isMemoryAllocationError(new Error('WebAssembly.Memory(): could not allocate memory')), 'should match the observed CI error')
    assert(isMemoryAllocationError(new Error('Out of memory')), 'should match "Out of memory"')
    assert(!isMemoryAllocationError(new Error('ENOENT: no such file')), 'should not match unrelated errors')
  },
})

// ---------------------------------------------------------------------------
// Unit tests: CLI argument parsing (args.ts)
// ---------------------------------------------------------------------------

// Test 12: space-delimited form — `--key value`
tests.push({
  name: 'args: parses space-delimited flags',
  run() {
    const args = parseArgs(['--input', '/tmp/icon.png', '--format', 'ico', '--out', '/tmp/out'])
    assert(args.input === '/tmp/icon.png', `input: ${args.input}`)
    assert(args.format === 'ico', `format: ${args.format}`)
    assert(args.out === '/tmp/out', `out: ${args.out}`)
  },
})

// Test 13: concatenated form — `--key=value` (backward compatibility)
tests.push({
  name: 'args: parses concatenated flags',
  run() {
    const args = parseArgs(['--input=/tmp/icon.png', '--format=icns', '--out=/tmp/out'])
    assert(args.input === '/tmp/icon.png', `input: ${args.input}`)
    assert(args.format === 'icns', `format: ${args.format}`)
    assert(args.out === '/tmp/out', `out: ${args.out}`)
  },
})

// Test 14: mixed forms and values containing characters that used to need escaping
tests.push({
  name: 'args: handles mixed forms, spaces, and "=" in values',
  run() {
    const args = parseArgs(['--input', '/tmp/my icons/a=b.png', '--format=set', '--out', '/out dir'])
    assert(args.input === '/tmp/my icons/a=b.png', `input: ${args.input}`)
    assert(args.format === 'set', `format: ${args.format}`)
    assert(args.out === '/out dir', `out: ${args.out}`)
  },
})

// Test 15: a flag with no value (followed by another flag) yields an empty string
tests.push({
  name: 'args: missing value does not swallow the next flag',
  run() {
    const args = parseArgs(['--input', '--format', 'ico'])
    assert(args.input === '', `expected empty input, got: ${args.input}`)
    assert(args.format === 'ico', `format: ${args.format}`)
  },
})

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function run(): Promise<void> {
  // icon-tool.js is a sibling of this compiled e2e.js in the out/ directory
  const toolPath = join(dirname(process.argv[1]), 'icon-tool.js')
  if (!existsSync(toolPath)) {
    console.error(`icon-tool.js not found at: ${toolPath}`)
    process.exit(1)
  }

  // Create temp directory for all test outputs
  const tmpDir = mkdtempSync(join(tmpdir(), 'icons-e2e-'))

  // Write fixtures to temp dir
  const pngFixture = join(tmpDir, 'fixture-1024.png')
  const svgFixture = join(tmpDir, 'fixture.svg')
  writeFileSync(pngFixture, makeSolidPng(1024))
  writeFileSync(svgFixture, Buffer.from(TEST_SVG))

  let failed = 0
  for (const t of tests) {
    try {
      await t.run(tmpDir, toolPath, pngFixture, svgFixture)
      console.log(`  PASS  ${t.name}`)
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err)
      console.error(`  FAIL  ${t.name}\n        ${msg}`)
      failed++
    }
  }

  // Cleanup
  try { rmSync(tmpDir, { recursive: true }) } catch { /* ignore */ }

  console.log('')
  if (failed > 0) {
    console.error(`${failed} of ${tests.length} test(s) failed.`)
    process.exit(1)
  }
  console.log(`All ${tests.length} tests passed.`)
}

run().catch((err: unknown) => {
  console.error(err instanceof Error ? err.stack || err.message : String(err))
  process.exit(1)
})
