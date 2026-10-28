# Where the license files come from

`LICENSES/` at the root of the squirrel.windows bundle is laid out by `build.ps1` at build time.
`MANIFEST.tsv` says which components each binary contains. `scripts/verify-licenses.sh` checks
the bundle at the end of the build and again in CI on the zip that is uploaded.

No license text is kept in the electron-builder-binaries repository. Every file is copied unchanged
from the upstream source at the version Squirrel.Windows 2.0.1 pins (`src/*/*.csproj`,
`src/*/packages.config`, the `vendor/nuget` submodule, `src/Setup/wtl90`):

- "build": taken from `build.ps1`'s own pinned inputs.
- every other file: downloaded by `build.ps1` from the URL in `UPSTREAM.tsv` and checked against the
  SHA-256 there (and, for a file taken out of a zip, nupkg or source file, the SHA-256 of that download
  too). The build fails on any mismatch or missing file.

| Component | File | Source |
|---|---|---|
| `squirrel-windows` | `COPYING` | build: Squirrel.Windows source at tag `$SquirrelVersion` (2.0.1), `COPYING` |
| `semver` | `LICENSE.md` | build: Squirrel.Windows source, `src/StubExecutable/LICENSE.md` (zmarko/semver, vendored in `src/StubExecutable`) |
| `7-zip` | `License.txt` | build: the pinned 7-Zip x64 installer (`7z<ver>-x64.exe`, SHA-256 in `build.ps1`) |
| `nuget-commandline` | `NOTICES.txt` | build: the pinned NuGet.CommandLine 7.9.0 package (`NOTICES.txt`, SHA-256 in `build.ps1`) |
| `nuget-commandline` | `LICENSE.txt` | NuGet/NuGet.Client at tag 7.9.0.83 (= commit `977537e19c6b`, the commit named in the package's nuspec; `nuget.exe` FileVersion is 7.9.0.83) |
| `nuget-commandline` | `LICENSE-2.0.txt` | the Apache License 2.0 text from the ASF website source (apache/www-site at `dbb00435`, `content/licenses/LICENSE-2.0.txt`, the file served at https://www.apache.org/licenses/LICENSE-2.0.txt); the package declares the license expression `Apache-2.0` |
| `nuget-squirrel` | `LICENSE.txt`, `COPYRIGHT.txt` | paulcbetts/NuGet at `50f8d9e438fe` (the `vendor/nuget` submodule commit of Squirrel.Windows 2.0.1, built as `NuGet.Squirrel.dll`) |
| `sharpcompress` | `LICENSE.txt` | adamhathcock/sharpcompress at tag 0.17.1 (SharpCompress 0.17.1) |
| `mono-cecil` | `LICENSE.txt` | jbevain/cecil at tag 0.11.2 (Mono.Cecil 0.11.2) |
| `deltacompressiondotnet` | `README.md` | taspeotis/DeltaCompressionDotNet at tag 1.1.0 (DeltaCompressionDotNet 1.1.0: its "License" section declares MS-PL; tag 1.1.0 has no license file) |
| `deltacompressiondotnet` | `LICENSE` | taspeotis/DeltaCompressionDotNet at `7215d81cc08e` (the MS-PL text, added by the author in 2016) |
| `microsoft-web-xdt` | `Microsoft.Web.Xdt.nuspec` | the nuspec inside the `Microsoft.Web.Xdt` 2.1.1 package from nuget.org, which carries the copyright and the license URL (http://go.microsoft.com/fwlink/?LinkId=273778). The package ships no license file. |
| `wpfanimatedgif` | `LICENSE.txt` | XamlAnimatedGif/WpfAnimatedGif at `12408d52d659` ("Bump version to 1.4.15"; WpfAnimatedGif 1.4.15 has no tag) |
| `octokit` | `LICENSE.txt` | octokit/octokit.net at tag v0.10.0 (identical to `LICENSE.txt` in the `Octokit` 0.10.0 package) |
| `simplejson` | `LICENSE.txt`, `NOTICE.txt` | facebook-csharp-sdk/simple-json at `f739f0b2924b` ("bumped version to v0.38.0"; v0.38.0 has no tag). Vendored as `src/Squirrel/SimpleJson`. |
| `splat` | `COPYING` | reactiveui/splat at tag 1.6.2 (Splat 1.6.2, the version in `src/Update/packages.config`; a subset is vendored as `src/Squirrel/SimpleSplat`) |
| `mono-options` | `NOTICE.txt` | lines 1-31 of `src/Update/Mono.Options/Options.cs` in Squirrel.Windows 2.0.1 (the file's copyright and MIT license header; `src/SyncReleases/Mono.Options/Options.cs` has the same header) |
| `markdownsharp` | `NOTICE.txt` | lines 1-82 of `src/Squirrel/MarkdownSharp.cs` in Squirrel.Windows 2.0.1 (the file's copyright and license header) |
| `bsdiff` | `ReadMe.txt` | LogosBible/bsdiff.net at `29852ed7285c` (the bsdiff.net commit before Squirrel.Windows adapted `src/Squirrel/BinaryPatchUtility.cs` from it in July 2014: Colin Percival's bsdiff license and the bsdiff.net MIT license) |
| `wtl` | `CPL.TXT` | `CPL.TXT` in `WTL90_4140_Final.zip` (WTL 9.0.4140 Final, SHA-1 `cd1194b140f77047bdea94efbf862a90dab8f629`) from SourceForge. Its 22 `Include/*.h` headers are identical to `src/Setup/wtl90` in Squirrel.Windows 2.0.1. |
| `unzip-zlib` | `NOTICE.txt` | lines 5-38 of `src/Setup/unzip.cpp` in Squirrel.Windows 2.0.1 (Lucian Wischik's zlib-derived unzip and the zlib 1.1.3 license) |

## Source code of the WTL headers

`Setup.exe` is built with the Windows Template Library (WTL) 9.0.4140 headers, which are licensed
under the Common Public License 1.0 (`LICENSES/wtl/CPL.TXT`). Their source code is available from:

- https://sourceforge.net/projects/wtl/files/WTL%209.0/WTL%209.0.4140%20Final/WTL90_4140_Final.zip
- https://github.com/Squirrel/Squirrel.Windows/tree/2.0.1/src/Setup/wtl90

When Squirrel.Windows or a pinned download changes version, update `UPSTREAM.tsv` (and this file)
from the new version, and `MANIFEST.tsv` if the merged assemblies change.
