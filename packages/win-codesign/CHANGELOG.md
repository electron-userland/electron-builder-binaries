# win-codesign

## 1.3.3

### Patch Changes

- [#251](https://github.com/electron-userland/electron-builder-binaries/pull/251) [`987b1db`](https://github.com/electron-userland/electron-builder-binaries/commit/987b1dbf1e144b85fae30110680bf479c26103e3) Thanks [@claude](https://github.com/apps/claude)! - fix(win-codesign): ship the third-party licenses of every bundled binary. Each bundle now has a `LICENSES/` directory (`MANIFEST.tsv` mapping every binary to its component, `LICENSES/<component>/` with the license files, `SOURCES.tsv` with each component's version and source), and every build and the CI bundle tests fail if a binary is shipped without its license (`scripts/verify-licenses.sh`). The macOS and Linux `osslsigncode` bundles now include `COPYING.txt`, the full GPLv3 text, as well as `LICENSE.txt`. Both are taken from the `osslsigncode` tag that was built rather than from `master`. The OpenSSL and libp11 licenses move from `lib/LICENSE.*.txt` to `LICENSES/openssl/` and `LICENSES/libp11/`. The Windows `osslsigncode` bundles, which shipped no license at all, now include the `osslsigncode` license and the OpenSSL and zlib licenses of the MSYS2 packages that provide the bundled DLLs. The rcedit `LICENSE` is fetched from the `v<version>` release tag instead of `master` and moves to `LICENSES/rcedit/`. The ATS bundle keeps the package's `LICENSE.md`, which was dropped before. The .NET runtime bundle also lays out its `LICENSE.txt` and `ThirdPartyNotices.txt` under `LICENSES/dotnet-runtime/`. The Windows SDK tools in the Windows Kits bundle now ship with the Windows SDK's license terms, copied verbatim from the installed SDK's `Licenses/<version>/` directory for the SDK version the tools come from into `LICENSES/windows-sdk/`, and the build fails if that directory is missing or empty.

## 1.3.2

### Patch Changes

- [#237](https://github.com/electron-userland/electron-builder-binaries/pull/237) [`2ab35a0`](https://github.com/electron-userland/electron-builder-binaries/commit/2ab35a08633afd920c2ef64b5f7b8c9354343b51) Thanks [@claude](https://github.com/apps/claude)! - fix(win-codesign): bundle OpenSSL 3.5 LTS with the Linux `osslsigncode` so it starts on distros without OpenSSL 1.1 (Ubuntu 22.04 and later). The 1.3.x Linux bundles linked the build image's `libcrypto.so.1.1` and `libcurl.so.4` but shipped an empty `lib/`, because `bundle-osslsigncode-libs.sh` copied the libraries next to the output zip instead of into the directory being zipped, so the binary failed with "libcrypto.so.1.1: cannot open shared object file". Linux now uses the same model as macOS: OpenSSL (same pinned version and checksum) built shared with the legacy provider compiled in, libp11's `pkcs11prov` built against it in `lib/ossl-modules`, and `osslsigncode` linked with RUNPATH `$ORIGIN/../lib` (with OpenSSL 3 it no longer needs libcurl). The bundle ships the OpenSSL and libp11 license texts. The build fails if any binary or bundled library needs a non-base-system library that is not in the bundle, has an absolute RUNPATH, or needs glibc newer than 2.31; CI smoke-tests every Linux bundle in a clean `ubuntu:24.04` container (legacy PKCS#12 and PEM file signing, plus SoftHSM-backed PKCS#11 signing on amd64/arm64), and arm64 now builds on a native runner

- [#240](https://github.com/electron-userland/electron-builder-binaries/pull/240) [`c37165b`](https://github.com/electron-userland/electron-builder-binaries/commit/c37165b6b24d8cd99504adc640165b50a0927c20) Thanks [@claude](https://github.com/apps/claude)! - fix(win-codesign): update `osslsigncode` from 2.11 to 2.14 on all platforms and the bundled .NET runtime (used by Azure Trusted Signing under Wine) from 8.0.28 to 8.0.33. osslsigncode 2.12 fixes CVE-2026-39853 (buffer overflow while extracting message digests during `verify`), 2.13 fixes integer overflows and double frees in APPX processing and memory corruption in PE page hash computation (CVE-2026-39855, CVE-2026-39856), and 2.14 fixes an APPX memory leak; the `sign` options electron-builder passes are unchanged (2.14 only drops the verification options from `attach-signature`). .NET 8.0.29 through 8.0.33 are all security releases. The .NET asset is renamed accordingly, from `dotnet-runtime-win-x64-8_0_28.zip` to `dotnet-runtime-win-x64-8_0_33.zip`. The stale `2.9` defaults in the per-platform build scripts and the Linux Dockerfile now match the 2.14 default used by CI

## 1.3.1

### Patch Changes

- [#235](https://github.com/electron-userland/electron-builder-binaries/pull/235) [`6368a89`](https://github.com/electron-userland/electron-builder-binaries/commit/6368a8972801962e67530b07cb965eb50c32edd0) Thanks [@claude](https://github.com/apps/claude)! - fix(win-codesign): bundle OpenSSL 3.5 LTS with the macOS `osslsigncode` so the darwin bundles no longer require Homebrew's `openssl@3` at a matching version. Previous builds loaded `/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib` (`/usr/local/opt/...` on Intel) and aborted with `dyld: Symbol not found: _OPENSSL_sk_set_thunks` once Homebrew moved `openssl@3` from 3.6 to the 3.5 LTS line, or with "Library not loaded" when Homebrew OpenSSL was not installed at all. The bundle now also ships libp11's `pkcs11prov` provider built against the same OpenSSL, so PKCS#11 signing (`-pkcs11module`) works without `OPENSSL_MODULES` or Homebrew libp11. It includes the OpenSSL and libp11 license texts, and the launcher clears quarantine on the bundled libraries as well as the binary. The build fails if anything links a non-system, non-bundled dylib, embeds a Homebrew path, or targets a macOS newer than 11.0; CI smoke-tests file and SoftHSM-backed PKCS#11 signing, and the minimum macOS version drops to 11.0

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
