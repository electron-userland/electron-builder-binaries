---
"nsis": patch
---

feat(nsis): update the bundled NSIS from 3.12 to 3.13 and publish two bundles. `nsis-bundle-3.13.tar.gz` is the default and builds `makensis` (Windows, Linux and macOS) and the stubs with `NSIS_CONFIG_LOG=no`. `nsis-bundle-3.13-log.tar.gz` builds them with `NSIS_CONFIG_LOG=yes`, which `LogSet` / `LogText` (electron-builder's `nsis.installerDebugLogging`) need. Everything else in the two bundles is identical. NSIS 3.13 fixes an `nsExec::ExecToLog` crash (bug #1323), updates the Italian and Korean translations and makes scons `TARGET_ARCH` the default `makensis` target (still `x86-unicode` here). The Korean MultiUser strings from `nsis-lang-fixes` are dropped because NSIS 3.13 ships its own translation of them, which already took precedence.
