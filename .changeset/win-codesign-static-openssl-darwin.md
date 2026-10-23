---
"win-codesign": patch
---

fix(win-codesign): bundle OpenSSL 3.5 LTS with the macOS `osslsigncode` so the darwin bundles no longer require Homebrew's `openssl@3` at a matching version. Previous builds loaded `/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib` (`/usr/local/opt/...` on Intel) and aborted with `dyld: Symbol not found: _OPENSSL_sk_set_thunks` once Homebrew moved `openssl@3` from 3.6 to the 3.5 LTS line, or with "Library not loaded" when Homebrew OpenSSL was not installed at all. The bundle now also ships libp11's `pkcs11prov` provider built against the same OpenSSL, so PKCS#11 signing (`-pkcs11module`) works without `OPENSSL_MODULES` or Homebrew libp11. The build fails if anything links a non-system, non-bundled dylib, CI smoke-tests file and SoftHSM-backed PKCS#11 signing, and the minimum macOS version drops to 11.0
