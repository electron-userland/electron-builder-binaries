// wasm-vips is a pthreads build: its WebAssembly.Memory is `shared` with
// initial === maximum, so V8 commits the entire 1 GiB region up front (a shared
// SharedArrayBuffer can't be relocated once it is handed to worker threads, so
// the backing store cannot grow on demand). That 1 GiB is baked into the wasm
// binary's memory import and cannot be lowered at runtime.
//
// When several icon-tool.js processes run at once (electron-builder spawns one
// process per icon and its test suite fans these out in parallel), each one tries
// to commit its own gigabyte. On memory-constrained CI runners — Windows in
// particular, where commit charge is bounded by RAM + page file — the OS refuses
// the allocation and the process dies with "WebAssembly.Memory(): could not
// allocate memory".
//
// The failures are transient: each conversion is short-lived, so a process that
// briefly backs off gets its memory once peers finish and decommit. These helpers
// retry init with exponential backoff and full jitter to decorrelate concurrent
// processes' retries (the AWS "full jitter" strategy).

export function isMemoryAllocationError(err: unknown): boolean {
  const message = err instanceof Error ? err.message : String(err)
  return /could not allocate memory|out of memory|cannot allocate|WebAssembly\.Memory/i.test(message)
}

export interface RetryOptions {
  attempts?: number
  baseDelayMs?: number
  maxDelayMs?: number
  // Injectable for tests; default to real timers / RNG in production.
  sleep?: (ms: number) => Promise<void>
  random?: () => number
}

const defaultSleep = (ms: number): Promise<void> => new Promise(resolve => setTimeout(resolve, ms))

// Run `fn`, retrying only when it fails with a host memory-allocation error.
// Non-allocation errors propagate immediately so real bugs are never masked.
export async function retryOnAllocationFailure<T>(fn: () => Promise<T>, options: RetryOptions = {}): Promise<T> {
  const attempts = options.attempts ?? 12
  const baseDelayMs = options.baseDelayMs ?? 200
  const maxDelayMs = options.maxDelayMs ?? 2500
  const sleep = options.sleep ?? defaultSleep
  const random = options.random ?? Math.random

  let lastError: unknown
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      return await fn()
    } catch (err) {
      lastError = err
      if (!isMemoryAllocationError(err) || attempt === attempts - 1) {
        throw err
      }
      // Full jitter: delay uniformly in [0, min(cap, base * 2^attempt)).
      const ceiling = Math.min(maxDelayMs, baseDelayMs * 2 ** attempt)
      await sleep(Math.floor(random() * ceiling))
    }
  }
  // Unreachable: the loop either returns or throws on the final attempt.
  throw lastError
}
