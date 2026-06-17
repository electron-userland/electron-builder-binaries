// Parse CLI flags, accepting both the concatenated `--key=value` form and the
// space-delimited `--key value` form so callers don't have to build
// `--input=<path>` strings. Every flag this tool understands takes a value, so a
// bare `--key` consumes the following token as its value — unless that token is
// itself a flag, in which case the value is treated as empty (the caller-facing
// validation in cli.ts reports the missing argument).
export function parseArgs(argv: string[]): Record<string, string> {
  const args: Record<string, string> = {}
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (!arg.startsWith('--')) {
      continue
    }
    const eq = arg.indexOf('=')
    if (eq !== -1) {
      // --key=value (value may itself contain '=', so split on the first only)
      args[arg.slice(2, eq)] = arg.slice(eq + 1)
      continue
    }
    // --key value
    const key = arg.slice(2)
    const next = argv[i + 1]
    if (next !== undefined && !next.startsWith('--')) {
      args[key] = next
      i++
    } else {
      args[key] = ''
    }
  }
  return args
}
