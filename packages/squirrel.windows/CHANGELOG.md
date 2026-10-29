# squirrel.windows

## 1.2.1

### Patch Changes

- [#251](https://github.com/electron-userland/electron-builder-binaries/pull/251) [`987b1db`](https://github.com/electron-userland/electron-builder-binaries/commit/987b1dbf1e144b85fae30110680bf479c26103e3) Thanks [@claude](https://github.com/apps/claude)! - fix(squirrel.windows): ship the license of every binary in the bundle. A new `LICENSES/` directory at the zip root has `MANIFEST.tsv`, which maps each binary to its components, and a license directory per component: Squirrel.Windows (MIT), 7-Zip, NuGet (`nuget.exe` now comes from the pinned NuGet.CommandLine 7.9.0 package, the same file, so its `NOTICES.txt` ships with it), the assemblies ILRepack merges into `Squirrel.exe`, `Squirrel-Mono.exe` and `SyncReleases.exe` (NuGet.Squirrel, SharpCompress, Mono.Cecil, DeltaCompressionDotNet, Microsoft.Web.Xdt, WpfAnimatedGif, Octokit), the sources Squirrel.Windows vendors (Mono.Options, SimpleJson, Splat, MarkdownSharp, bsdiff), semver in `StubExecutable.exe`, and WTL and the zlib-derived unzip in `Setup.exe`. Each text is downloaded at build time from the upstream source at the version Squirrel.Windows 2.0.1 pins and checked against its SHA-256 (`LICENSES/UPSTREAM.tsv` lists the URLs and checksums, `LICENSES/SOURCES.md` says why); no license text is kept in this repository. The zip no longer contains the unused `squirrel.windows.2.0.1.nupkg`, which carried a stale 7-Zip 16.04, WiX 3.10, rcedit and signtool without their licenses, or `Squirrel.com` (a renamed Visual Studio `devenv.com` that electron-builder never runs). The build fails if a binary has no license entry (`scripts/verify-licenses.sh`), and CI checks the uploaded zip again

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
