# squirrel.windows

## 1.2.0

### Minor Changes

- [#242](https://github.com/electron-userland/electron-builder-binaries/pull/242) [`4c0df62`](https://github.com/electron-userland/electron-builder-binaries/commit/4c0df62e3cdf75d301d019e20dceb147f6e8916f) Thanks [@claude](https://github.com/apps/claude)! - feat(squirrel.windows): bundle a pinned, checksum-verified 7-Zip 26.05 (x64 and arm64) and nuget.exe 7.9.0

  The vendored `7z.exe`/`7z.dll` were previously copied from whatever 7-Zip the build runner had installed (26.01 in 1.1.1). They now come from the official 7-Zip 26.05 installers at github.com/ip7z/7zip, verified against pinned SHA-256 values, with the FileVersion and PE architecture checked at build time. This picks up the 26.02 XZ decoder fix (CVE-2026-14266) and later upstream fixes. The bundle keeps the same layout (`7z.exe`, `7z.dll`, `7z-x64.exe`, `7z-x64.dll`, `7z-LICENSE.txt`) and adds native `7z-arm64.exe`/`7z-arm64.dll`, which electron-builder selects on arm64 Windows hosts. The pinned standalone `nuget.exe` moves from 6.14.0 to 7.9.0.

## 1.1.1

### Patch Changes

- [#203](https://github.com/electron-userland/electron-builder-binaries/pull/203) [`6ae596e`](https://github.com/electron-userland/electron-builder-binaries/commit/6ae596e5ae49d11b3b186980d95a98d20422ba53) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(squirrel.windows): bundle a pinned, checksum-verified standalone nuget.exe (v6.14.0) instead of the Chocolatey shim

## 1.1.0

### Minor Changes

- [#199](https://github.com/electron-userland/electron-builder-binaries/pull/199) [`d784f0f`](https://github.com/electron-userland/electron-builder-binaries/commit/d784f0fd1bf9ffd8b269384d93350c083941beff) Thanks [@mmaietta](https://github.com/mmaietta)! - feat(squirrel.windows): bundle nuget.exe and 7-Zip binaries into vendor directory

### Patch Changes

- [#201](https://github.com/electron-userland/electron-builder-binaries/pull/201) [`4a54715`](https://github.com/electron-userland/electron-builder-binaries/commit/4a54715e95268fcba942e45da6e24f3387148d83) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(squirrel): use `zip` for squirrel.windows archive

## 1.0.0

### Major Changes

- [#67](https://github.com/electron-userland/electron-builder-binaries/pull/67) [`c3e0acb`](https://github.com/electron-userland/electron-builder-binaries/commit/c3e0acb129c9418cd7c39bc23270312dfff9b98d) Thanks [@mmaietta](https://github.com/mmaietta)! - feat(squirrel): updating to 2.0.1 with patch applied
