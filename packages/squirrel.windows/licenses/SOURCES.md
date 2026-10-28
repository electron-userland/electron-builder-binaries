# Where the license files come from

`build.ps1` copies this directory to `LICENSES/` at the root of the squirrel.windows bundle.
`MANIFEST.tsv` says which components each binary contains. `scripts/verify-licenses.sh` checks
the bundle at the end of the build and again in CI on the zip that is uploaded.

All files are copied unchanged from the upstream source at the version Squirrel.Windows 2.0.1
pins (`src/*/*.csproj`, the `vendor/nuget` submodule, `src/Setup/wtl90`). Files marked "build"
are not committed here: `build.ps1` copies them from its own pinned inputs.

| Component | File | Source |
|---|---|---|
| `squirrel-windows` | `COPYING` | build: Squirrel.Windows source at tag `$SquirrelVersion` (2.0.1), `COPYING` |
| `semver` | `LICENSE.md` | build: Squirrel.Windows source, `src/StubExecutable/LICENSE.md` (zmarko/semver, vendored in `src/StubExecutable`) |
| `7-zip` | `License.txt` | build: the pinned 7-Zip x64 installer (`7z<ver>-x64.exe`, SHA-256 in `build.ps1`) |
| `nuget-commandline` | `NOTICES.txt` | build: the pinned NuGet.CommandLine 7.9.0 package (`NOTICES.txt`, SHA-256 in `build.ps1`) |
| `nuget-commandline` | `LICENSE.txt` | https://github.com/NuGet/NuGet.Client/blob/7.9.0.83/LICENSE.txt (tag 7.9.0.83 = commit `977537e19c6b`, the commit named in the package's nuspec; `nuget.exe` FileVersion is 7.9.0.83) |
| `nuget-commandline` | `LICENSE-2.0.txt` | https://www.apache.org/licenses/LICENSE-2.0.txt (the package declares the license expression `Apache-2.0`) |
| `nuget-squirrel` | `LICENSE.txt`, `COPYRIGHT.txt` | https://github.com/paulcbetts/NuGet at `50f8d9e438fe948d7109501bd10f6024d0585b70` (the `vendor/nuget` submodule commit of Squirrel.Windows 2.0.1, built as `NuGet.Squirrel.dll`) |
| `sharpcompress` | `LICENSE.txt` | https://github.com/adamhathcock/sharpcompress/blob/0.17.1/LICENSE.txt (SharpCompress 0.17.1) |
| `mono-cecil` | `LICENSE.txt` | https://github.com/jbevain/cecil/blob/0.11.2/LICENSE.txt (Mono.Cecil 0.11.2) |
| `deltacompressiondotnet` | `README.md` | https://github.com/taspeotis/DeltaCompressionDotNet/blob/1.1.0/README.md (DeltaCompressionDotNet 1.1.0: its "License" section declares MS-PL; tag 1.1.0 has no license file) |
| `deltacompressiondotnet` | `LICENSE` | https://github.com/taspeotis/DeltaCompressionDotNet/blob/7215d81cc08e09d220565cf7b7ebe4bbd5f499de/LICENSE (the MS-PL text, added by the author in 2016) |
| `microsoft-web-xdt` | `Microsoft.Web.Xdt.nuspec` | the `Microsoft.Web.Xdt` 2.1.1 package from nuget.org: its nuspec, which carries the copyright and the license URL (http://go.microsoft.com/fwlink/?LinkId=273778). The package ships no license file. |
| `wpfanimatedgif` | `LICENSE.txt` | https://github.com/XamlAnimatedGif/WpfAnimatedGif/blob/12408d52d65919ae89a3b91b9604045a799e47c6/LICENSE.txt ("Bump version to 1.4.15"; WpfAnimatedGif 1.4.15 has no tag) |
| `octokit` | `LICENSE.txt` | the `Octokit` 0.10.0 package from nuget.org (identical to https://github.com/octokit/octokit.net/blob/v0.10.0/LICENSE.txt) |
| `simplejson` | `LICENSE.txt`, `NOTICE.txt` | https://github.com/facebook-csharp-sdk/simple-json at `f739f0b2924bcfa33204e86b8b73aa98be68abac` ("bumped version to v0.38.0"; v0.38.0 has no tag). Vendored as `src/Squirrel/SimpleJson`. |
| `splat` | `COPYING` | https://github.com/reactiveui/splat/blob/1.6.2/COPYING (Splat 1.6.2, the version in `src/Update/packages.config`; a subset is vendored as `src/Squirrel/SimpleSplat`) |
| `mono-options` | `NOTICE.txt` | lines 1-31 of `src/Update/Mono.Options/Options.cs` in Squirrel.Windows 2.0.1 (the file's copyright and MIT license header; `src/SyncReleases/Mono.Options/Options.cs` has the same header) |
| `markdownsharp` | `NOTICE.txt` | lines 1-82 of `src/Squirrel/MarkdownSharp.cs` in Squirrel.Windows 2.0.1 (the file's copyright and license header) |
| `bsdiff` | `ReadMe.txt` | https://github.com/LogosBible/bsdiff.net/blob/29852ed7285c661b52e893b391c968fb68387f72/ReadMe.txt (the bsdiff.net commit before Squirrel.Windows adapted `src/Squirrel/BinaryPatchUtility.cs` from it in July 2014: Colin Percival's bsdiff license and the bsdiff.net MIT license) |
| `wtl` | `CPL.TXT` | `WTL90_4140_Final.zip` (WTL 9.0.4140 Final, SHA-1 `cd1194b140f77047bdea94efbf862a90dab8f629`) from https://sourceforge.net/projects/wtl/files/WTL%209.0/WTL%209.0.4140%20Final/. Its 22 `Include/*.h` headers are identical to `src/Setup/wtl90` in Squirrel.Windows 2.0.1. |
| `wtl` | `SOURCE.txt` | where to get the WTL source (CPL-1.0 section 3) |
| `unzip-zlib` | `NOTICE.txt` | lines 5-38 of `src/Setup/unzip.cpp` in Squirrel.Windows 2.0.1 (Lucian Wischik's zlib-derived unzip and the zlib 1.1.3 license) |

When Squirrel.Windows or a pinned download changes version, update these files from the new
version and update `MANIFEST.tsv` if the merged assemblies change.
