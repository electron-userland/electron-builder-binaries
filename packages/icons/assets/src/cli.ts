import { existsSync, mkdirSync, readFileSync } from 'fs'
import { extname } from 'path'
import { svgToPng } from './svg'
import { createIcns } from './icns'
import { createIco } from './ico'
import { createLinuxSet } from './linux'
import { extractLargestPngFromIcns, describeIcnsEntries } from './icns-input'
import { parseArgs } from './args'
import { debug } from './log'

const VALID_FORMATS = ['icns', 'ico', 'set'] as const
type Format = typeof VALID_FORMATS[number]

// Largest recommended rasterization width for SVG → PNG before icon conversion.
// 1024px gives all ICNS/ICO sizes enough headroom.
const SVG_RASTER_WIDTH = 1024

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2))

  const input = args['input']
  const format = args['format'] as Format
  const outDir = args['out']

  if (!input || !format || !outDir) {
    console.error('Usage: node icon-tool.js --input <path> --format <icns|ico|set> --out <dir>')
    process.exit(1)
  }

  if (!VALID_FORMATS.includes(format)) {
    console.error(`Invalid format "${format}". Valid formats: ${VALID_FORMATS.join(', ')}`)
    process.exit(1)
  }

  if (!existsSync(input)) {
    console.error(`Input file not found: ${input}`)
    process.exit(1)
  }

  mkdirSync(outDir, { recursive: true })

  const ext = extname(input).toLowerCase()
  debug(`input=${input} format=${format} ext=${ext} out=${outDir}`)
  let pngBuffer: Buffer

  if (ext === '.svg') {
    const svgBuffer = readFileSync(input)
    pngBuffer = await svgToPng(svgBuffer, SVG_RASTER_WIDTH)
  } else if (ext === '.png') {
    pngBuffer = readFileSync(input)
  } else if (ext === '.icns') {
    const icnsBuffer = readFileSync(input)
    const { png, entries } = extractLargestPngFromIcns(icnsBuffer)
    if (!png) {
      console.error(
        `Could not extract a PNG frame from ICNS file. Frames found: [${describeIcnsEntries(entries)}]. ` +
          `This toolset can only read PNG-encoded ICNS frames; JPEG2000, ARGB, and legacy raw frames are not supported. ` +
          `Re-export the icon as a PNG/SVG source, or as an ICNS containing a PNG frame.`
      )
      process.exit(1)
    }
    pngBuffer = png
  } else {
    console.error(`Unsupported input format "${ext}". Supported: .png, .svg, .icns`)
    process.exit(1)
  }

  switch (format) {
    case 'icns':
      await createIcns(pngBuffer, outDir)
      break
    case 'ico':
      await createIco(pngBuffer, outDir)
      break
    case 'set':
      await createLinuxSet(pngBuffer, outDir)
      break
  }

  console.log(`Done: ${format} → ${outDir}`)
}

main().catch((err: Error) => {
  console.error('Error:', err.message || String(err))
  process.exit(1)
})
