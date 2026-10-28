# electron-builder-binaries

This repo provides the required toolsets that [electron-builder](http://github.com/electron-userland/electron-builder) downloads on demand (e.g. to code sign windows application, to make AppX, assemble DMGs, bundle AppImage, etc).

The toolset (in Releases) have their version and checksum hardcoded in electron-builder's code. This ensures that even if this repository or your network gets compromised, electron-builder tooling will not be affected.

The goals of this repo are:
- To provide a secure closed-loop tooling ecosystem that electron-builder can rely on.
- Serve toolsets on-demand to reduce (or remove entirely) the load/overhead of a pre-configuring a dev environment.

## Licensing

### Artifacts

All toolsets collected/stored/distributed from this repo retain their original licensing; their LICENSE or COPYING file(s) are downloaded and included within each toolset bundle within `artifacts` dir.

#### License guard (`scripts/verify-licenses.sh`)

Every binary a toolset bundle ships must come with the license of the component(s) it was built from. A bundle records this in a `LICENSES/` directory at its root:

| Path | Contents |
| --- | --- |
| `LICENSES/MANIFEST.tsv` | `<relative path><TAB><component>` for every binary. A path may be a glob (`*`, `?`, `[...]`; `*` also matches `/`). A binary built from several components (e.g. statically linked libraries) is listed once per component. |
| `LICENSES/<component>/` | That component's license files (at least one non-empty file), taken from its pinned upstream source / tag, the build image's `/usr/share/doc/<pkg>/copyright`, the package's own metadata, etc. Never written by hand. |
| `LICENSES/EXEMPT.tsv` | Optional. `<relative path or glob><TAB><reason>` for binaries deliberately shipped without license files while a decision is pending. Every exemption is printed on every run (and raised as a warning annotation in GitHub Actions). |

Blank lines and lines starting with `#` are ignored in both TSV files.

```sh
bash scripts/verify-licenses.sh <bundle-dir>          # check a bundle (run it at the end of a package's build)
bash scripts/verify-licenses.sh --list <bundle-dir>   # print the binaries it finds, to start a MANIFEST.tsv
```

Binaries are found by their magic bytes, whatever their name: ELF, Mach-O (including fat/universal) and PE/DOS (`MZ`, i.e. `.exe`/`.dll`). The check exits non-zero, naming every offending path, when a binary is neither listed nor exempted, when a listed component has no license files, or when a `MANIFEST.tsv` entry does not exist in the bundle (a glob: matches no binary). It is plain bash (Linux, macOS's bash 3.2, Git Bash on Windows) with no extra dependencies. Its tests run in CI on all three: `bash scripts/tests/verify-licenses-test.sh` (or `pnpm test:license-guard`).

### Repo License
This applies to configurations/scripts that compile and/or bundle toolsets.

Copyright 2026 electron-userland

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.