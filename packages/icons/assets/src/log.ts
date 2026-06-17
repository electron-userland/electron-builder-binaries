// Lightweight debug logger for the standalone icon-tool bundle.
//
// The bundle is intentionally dependency-free (shipped as a single Node script),
// so instead of pulling in the `debug` package we honor the same DEBUG env-var
// convention it uses. Enable with:
//   DEBUG=icons   (or icons:*, or *)
// Output goes to stderr so it never contaminates the tool's stdout.
const NAMESPACE = 'icons'

function isEnabled(): boolean {
  const spec = process.env.DEBUG
  if (!spec) {
    return false
  }
  let result = false
  for (const raw of spec.split(/[\s,]+/)) {
    if (!raw) {
      continue
    }
    const negate = raw.startsWith('-')
    const pattern = negate ? raw.slice(1) : raw
    const matches =
      pattern === '*' ||
      pattern === NAMESPACE ||
      (pattern.endsWith('*') && NAMESPACE.startsWith(pattern.slice(0, -1)))
    if (matches) {
      result = !negate
    }
  }
  return result
}

const enabled = isEnabled()

export function debug(message: string): void {
  if (enabled) {
    process.stderr.write(`  ${NAMESPACE} ${message}\n`)
  }
}
