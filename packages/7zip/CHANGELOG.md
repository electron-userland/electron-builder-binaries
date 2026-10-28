# 7zip

## 1.1.0

### Minor Changes

- [#239](https://github.com/electron-userland/electron-builder-binaries/pull/239) [`68be2f6`](https://github.com/electron-userland/electron-builder-binaries/commit/68be2f6e3cd0ad76ea2d9c6ef54aa9fc3476b840) Thanks [@claude](https://github.com/apps/claude)! - feat(7zip): update bundled 7-Zip from 24.09 to 26.05

  All platform bundles now ship 7-Zip 26.05 (released 2026-10-21), picking up upstream security fixes missing from 24.09, including CVE-2025-11001 / CVE-2025-11002 (ZIP symlink path traversal), CVE-2025-55188 (symlink handling) and CVE-2026-14266 (XZ decoder heap overflow). The pinned SHA-256 values for the upstream downloads are updated to match the official 26.05 release assets at github.com/ip7z/7zip.

## 1.0.1

### Patch Changes

- [#223](https://github.com/electron-userland/electron-builder-binaries/pull/223) [`781d4a3`](https://github.com/electron-userland/electron-builder-binaries/commit/781d4a313d199ce78c1dd635fb7d9ec716756e98) Thanks [@xpolb01](https://github.com/xpolb01)! - fix(7zip): bundle the correct architecture-specific `7za.exe` for win-x64 and win-arm64

  The `7zip-win-x64` and `7zip-win-arm64` bundles previously shipped the 32-bit x86 `7za.exe` from the root of the upstream `7z-extra` archive, capping 7-Zip's compression memory budget and quietly collapsing LZMA2 multithreading. The 64-bit and ARM64 console builds from the archive's `x64/` and `arm64/` subdirectories are now bundled instead; the root x86 binary remains the fallback only for `7zip-win-ia32`, where it is correct. Fixes [#222](https://github.com/electron-userland/electron-builder-binaries/issues/222).

## 1.0.0

### Major Changes

- [#196](https://github.com/electron-userland/electron-builder-binaries/pull/196) [`6121968`](https://github.com/electron-userland/electron-builder-binaries/commit/61219681d626614dfe28c69359ff3b4007361bc0) Thanks [@mmaietta](https://github.com/mmaietta)! - feat(7zip): introducing new 7zip portable bundle
