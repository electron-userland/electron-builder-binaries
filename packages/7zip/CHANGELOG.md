# 7zip

## 1.0.1

### Patch Changes

- [#223](https://github.com/electron-userland/electron-builder-binaries/pull/223) [`781d4a3`](https://github.com/electron-userland/electron-builder-binaries/commit/781d4a313d199ce78c1dd635fb7d9ec716756e98) Thanks [@xpolb01](https://github.com/xpolb01)! - fix(7zip): bundle the correct architecture-specific `7za.exe` for win-x64 and win-arm64

  The `7zip-win-x64` and `7zip-win-arm64` bundles previously shipped the 32-bit x86 `7za.exe` from the root of the upstream `7z-extra` archive, capping 7-Zip's compression memory budget and quietly collapsing LZMA2 multithreading. The 64-bit and ARM64 console builds from the archive's `x64/` and `arm64/` subdirectories are now bundled instead; the root x86 binary remains the fallback only for `7zip-win-ia32`, where it is correct. Fixes [#222](https://github.com/electron-userland/electron-builder-binaries/issues/222).

## 1.0.0

### Major Changes

- [#196](https://github.com/electron-userland/electron-builder-binaries/pull/196) [`6121968`](https://github.com/electron-userland/electron-builder-binaries/commit/61219681d626614dfe28c69359ff3b4007361bc0) Thanks [@mmaietta](https://github.com/mmaietta)! - feat(7zip): introducing new 7zip portable bundle
