import { execSync } from 'child_process'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'fs'
import { deflateSync } from 'zlib'
import { join, dirname } from 'path'
import { tmpdir } from 'os'
import { parseIcns, parseIco, parsePngDimensions } from './validate'

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

type Test = { name: string; run: (tmpDir: string, toolPath: string, pngFixture: string, svgFixture: string) => void }

const tests: Test[] = []

// Test 1: PNG → ICNS
tests.push({
  name: 'PNG → ICNS',
  run(tmpDir, toolPath, pngFixture) {
    const out = join(tmpDir, 'png-icns')
    mkdirSync(out)
    execSync(`node "${toolPath}" --input="${pngFixture}" --format=icns --out="${out}"`)
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
    execSync(`node "${toolPath}" --input="${pngFixture}" --format=ico --out="${out}"`)
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
    execSync(`node "${toolPath}" --input="${pngFixture}" --format=set --out="${out}"`)
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
    execSync(`node "${toolPath}" --input="${svgFixture}" --format=icns --out="${out}"`)
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
    execSync(`node "${toolPath}" --input="${svgFixture}" --format=ico --out="${out}"`)
    const file = join(out, 'icon.ico')
    if (!existsSync(file)) throw new Error('icon.ico from SVG was not created')
    const sizes = parseIco(readFileSync(file))
    if (!sizes.includes(256)) throw new Error(`ICO from SVG is missing 256px entry (found: ${sizes.join(', ')})`)
  },
})

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function run(): void {
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
      t.run(tmpDir, toolPath, pngFixture, svgFixture)
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

run()
