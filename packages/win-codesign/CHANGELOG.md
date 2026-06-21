# win-codesign

## 1.3.0

### Minor Changes

- [#210](https://github.com/electron-userland/electron-builder-binaries/pull/210) [`2073c30`](https://github.com/electron-userland/electron-builder-binaries/commit/2073c30ad704086dc33b0344ee92ad93b92bafbe) Thanks [@mmaietta](https://github.com/mmaietta)! - feat(win-codesign): add dotnet-runtime-win-x64 bundle for Azure Trusted Signing under Wine

- [#206](https://github.com/electron-userland/electron-builder-binaries/pull/206) [`f26145e`](https://github.com/electron-userland/electron-builder-binaries/commit/f26145e5214fc1d8bab064f38417dfd9f84e5229) Thanks [@mmaietta](https://github.com/mmaietta)! - feat(win-codesign): Add "Azure.CodeSigning.Dlib.dll" and "msft_authentication_extension_v2.dll" to bundle to support Azure Trusted Signing

### Patch Changes

- [#208](https://github.com/electron-userland/electron-builder-binaries/pull/208) [`83ac8c6`](https://github.com/electron-userland/electron-builder-binaries/commit/83ac8c653a2b5a1634d11f14e853647ea26271e2) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(win-codesign): bundle the full Microsoft.Trusted.Signing.Client `bin/<arch>` payload, pin the nupkg SHA-256 (fail-closed verification by default) and stop copying x64 ATS DLLs into the arm64 kit directory

- [#208](https://github.com/electron-userland/electron-builder-binaries/pull/208) [`83ac8c6`](https://github.com/electron-userland/electron-builder-binaries/commit/83ac8c653a2b5a1634d11f14e853647ea26271e2) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(win-codesign): add `--target` flag to build.sh and run kits/ats/rcedit on a dedicated x64 CI runner so arch-agnostic artifacts are produced exactly once, eliminating the race where the arm64 matrix job could overwrite the x64 job's identical outputs

- [#206](https://github.com/electron-userland/electron-builder-binaries/pull/206) [`f26145e`](https://github.com/electron-userland/electron-builder-binaries/commit/f26145e5214fc1d8bab064f38417dfd9f84e5229) Thanks [@mmaietta](https://github.com/mmaietta)! - chore(win-codesign): harden build-win-kits.sh with helper extraction, cleanup trap, and test coverage

## 1.2.1

### Patch Changes

- [#186](https://github.com/electron-userland/electron-builder-binaries/pull/186) [`a568ac2`](https://github.com/electron-userland/electron-builder-binaries/commit/a568ac27c711b40be9b0f77222add8ef8e7cdf65) Thanks [@mmaietta](https://github.com/mmaietta)! - chore(deploy): redeploying due to failed attest CJS->ESM module update

## 1.2.0

### Minor Changes

- [#182](https://github.com/electron-userland/electron-builder-binaries/pull/182) [`249606d`](https://github.com/electron-userland/electron-builder-binaries/commit/249606db4b2895a6b6c5de4b2a04164817c4b870) Thanks [@mmaietta](https://github.com/mmaietta)! - feat: add Windows arm64 support for signtool and osslsigncode

## 1.1.1

### Patch Changes

- [#156](https://github.com/electron-userland/electron-builder-binaries/pull/156) [`4f378ce`](https://github.com/electron-userland/electron-builder-binaries/commit/4f378cecc124b3c0424007da9b62aaf52854a8d2) Thanks [@mmaietta](https://github.com/mmaietta)! - chore: updating scripts w/ positional args, checksum matches, and general hardening

- [#152](https://github.com/electron-userland/electron-builder-binaries/pull/152) [`d1f6262`](https://github.com/electron-userland/electron-builder-binaries/commit/d1f6262334fc1aba5a1b59a36fecd9d174ea28e4) Thanks [@mmaietta](https://github.com/mmaietta)! - chore: embedding LICENSE/COPYING files within each toolset bundle

## 1.1.0

### Minor Changes

- [#132](https://github.com/electron-userland/electron-builder-binaries/pull/132) [`a7fcd40`](https://github.com/electron-userland/electron-builder-binaries/commit/a7fcd405058451839e93a2ec41f3b85ae4a757f9) Thanks [@mmaietta](https://github.com/mmaietta)! - feat: update osslsigncode to 2.11

## 1.0.0

### Major Changes

- [#72](https://github.com/electron-userland/electron-builder-binaries/pull/72) [`db64b8d`](https://github.com/electron-userland/electron-builder-binaries/commit/db64b8d4b82f1707d2eff4a072f3f2ebc7cc13d4) Thanks [@mmaietta](https://github.com/mmaietta)! - feat(win-codesign): upgrading WindowsKits to 10.0.26100.0 and osslsigncode 2.9 w/ openssl 3
