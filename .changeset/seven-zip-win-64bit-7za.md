---
"7zip": patch
---

fix(7zip): bundle the correct architecture-specific `7za.exe` for win-x64 and win-arm64

The `7zip-win-x64` and `7zip-win-arm64` bundles previously shipped the 32-bit x86 `7za.exe` from the root of the upstream `7z-extra` archive, capping 7-Zip's compression memory budget and quietly collapsing LZMA2 multithreading. The 64-bit and ARM64 console builds from the archive's `x64/` and `arm64/` subdirectories are now bundled instead; the root x86 binary remains the fallback only for `7zip-win-ia32`, where it is correct. Fixes [#222](https://github.com/electron-userland/electron-builder-binaries/issues/222).
