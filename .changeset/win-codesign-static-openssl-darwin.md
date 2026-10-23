---
"win-codesign": patch
---

fix(win-codesign): link OpenSSL 3.5 LTS statically into the macOS `osslsigncode` so the darwin bundles no longer require Homebrew's `openssl@3` at a matching version. Previous builds loaded `/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib` (`/usr/local/opt/...` on Intel) and aborted with `dyld: Symbol not found: _OPENSSL_sk_set_thunks` once Homebrew moved `openssl@3` from 3.6 to the 3.5 LTS line, or with "Library not loaded" when Homebrew OpenSSL was not installed at all. The build now fails if the binary links any non-system dylib, the bundle gets a sign/verify smoke test in CI, and the minimum macOS version drops to 11.0
