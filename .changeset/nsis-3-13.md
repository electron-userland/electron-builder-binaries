---
"nsis": minor
---

feat(nsis): update the bundled NSIS from 3.12 to 3.13, which fixes an `nsExec::ExecToLog` crash (bug #1323), updates the Italian and Korean translations and makes scons `TARGET_ARCH` the default `makensis` target (still `x86-unicode` for this bundle, which is built with the default `TARGET_ARCH=x86`). The release asset is now `nsis-bundle-3.13.tar.gz`. The Korean MultiUser strings from `nsis-lang-fixes` are dropped because NSIS 3.13 ships its own translation of them, which already took precedence
