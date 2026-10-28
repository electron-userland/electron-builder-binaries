# dmg-builder

## 1.2.7

### Patch Changes

- [#251](https://github.com/electron-userland/electron-builder-binaries/pull/251) [`987b1db`](https://github.com/electron-userland/electron-builder-binaries/commit/987b1dbf1e144b85fae30110680bf479c26103e3) Thanks [@claude](https://github.com/apps/claude)! - fix(dmg-builder): ship the license of every component in the bundle. The build deleted the pip packages' `.dist-info` directories, and with them the only copies of the MIT licenses of `ds_store`, `mac_alias`, `pyobjc-framework-Cocoa` and `pyobjc-framework-Quartz`; `pyobjc-core`'s wheel has none at all, and CPython's notices for the third-party code compiled into the interpreter and its extension modules (expat, libmpdec, mimalloc, Mersenne Twister, HACL*, ...) were never shipped. `LICENSES/` is now laid out per component (`python/` with CPython's `LICENSE`, `Doc/license.rst` and the HACL* notice, `openssl/`, `dmgbuild/`, `ds_store/`, `mac_alias/`, `pyobjc-core/`, `pyobjc-framework-Cocoa/`, `pyobjc-framework-Quartz/`) with a `LICENSES/MANIFEST.tsv` mapping every binary to its components; the package licenses are copied from their `.dist-info` before it is deleted, `pyobjc-core`'s `License.txt` comes from its SHA256-pinned sdist, CPython's from the checksum-verified source tree instead of a second download, and dmgbuild's `LICENSE` is fetched at the pinned commit instead of `master`. The build and its post-build check of the archives fail when a binary has no license (`scripts/verify-licenses.sh`). The license files moved from `LICENSES/LICENSE.<name>` to `LICENSES/<name>/`.

## 1.2.6

### Patch Changes

- [#241](https://github.com/electron-userland/electron-builder-binaries/pull/241) [`bae0827`](https://github.com/electron-userland/electron-builder-binaries/commit/bae0827ea4034ee59f15845afefdd2371f34cccf) Thanks [@claude](https://github.com/apps/claude)! - fix(dmg-builder): make the macOS 11.0 floor real and enforce it. The bundled `libcrypto`/`libssl` for `_ssl` and `_hashlib` were copied from the runner's Homebrew `openssl@3` (3.6.2, minos 15.0), so part of the runtime required macOS 15; OpenSSL 3.5.9 LTS is now built from source with `MACOSX_DEPLOYMENT_TARGET=11.0` and its license is included in `LICENSES/`. The post-build check in `build.sh` scanned the output folder, which only holds the tarball, so it never inspected a binary; it now extracts each shipped archive and fails on any Mach-O that links a Homebrew library or has a `minos` newer than the deployment target, and on an archive with no Mach-O files at all. CI self-tests the check against fixtures before building. Also bumps Python 3.14.2 → 3.14.10, moves dmgbuild to `cc96fa2` (the CLI `--detach-retries` default goes from 5 to 12, so the bundle file name becomes `dmgbuild-bundle-<arch>-cc96fa2.tar.gz`), pins ds_store 1.3.3, mac_alias 2.2.3 and pyobjc 12.2.2, and lists the installed package versions in `VERSION.txt`.

## 1.2.5

### Patch Changes

- [#194](https://github.com/electron-userland/electron-builder-binaries/pull/194) [`be9f070`](https://github.com/electron-userland/electron-builder-binaries/commit/be9f070f066084c921b06fe70233cd8600516893) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(dmg-builder): CJK license encoding in DMG builds: re-bundle CJK codec extensions, correct the `multibyte_encoding` → `multibyte` key-name bug in `licensing.py`, and add UTF-8 fallbacks so a missing codec never aborts the build.

## 1.2.4

### Patch Changes

- [#186](https://github.com/electron-userland/electron-builder-binaries/pull/186) [`a568ac2`](https://github.com/electron-userland/electron-builder-binaries/commit/a568ac27c711b40be9b0f77222add8ef8e7cdf65) Thanks [@mmaietta](https://github.com/mmaietta)! - chore(deploy): redeploying due to failed attest CJS->ESM module update

## 1.2.3

### Patch Changes

- [#181](https://github.com/electron-userland/electron-builder-binaries/pull/181) [`af42701`](https://github.com/electron-userland/electron-builder-binaries/commit/af427013d0bc0c05b2a7f42d1c4aa9f2537dcbfd) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(dmg-builder): patch dmgbuild core — correct size formula and ditto error propagation

## 1.2.2

### Patch Changes

- [#165](https://github.com/electron-userland/electron-builder-binaries/pull/165) [`05ef739`](https://github.com/electron-userland/electron-builder-binaries/commit/05ef7396d189c6026a7de6c0718b2f94586acf35) Thanks [@mmaietta](https://github.com/mmaietta)! - fix: do not delete uuid since it is lazily loaded in python 3.14.2 + mac_alias

## 1.2.1

### Patch Changes

- [#156](https://github.com/electron-userland/electron-builder-binaries/pull/156) [`4f378ce`](https://github.com/electron-userland/electron-builder-binaries/commit/4f378cecc124b3c0424007da9b62aaf52854a8d2) Thanks [@mmaietta](https://github.com/mmaietta)! - chore: updating scripts w/ positional args, checksum matches, and general hardening

- [#152](https://github.com/electron-userland/electron-builder-binaries/pull/152) [`d1f6262`](https://github.com/electron-userland/electron-builder-binaries/commit/d1f6262334fc1aba5a1b59a36fecd9d174ea28e4) Thanks [@mmaietta](https://github.com/mmaietta)! - chore: embedding LICENSE/COPYING files within each toolset bundle

- [#154](https://github.com/electron-userland/electron-builder-binaries/pull/154) [`86a52e2`](https://github.com/electron-userland/electron-builder-binaries/commit/86a52e2fb50bafc1fc3b1679f5b60fe56e8877b5) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(dmg-builder): fix deployment target to properly read/apply to build pipeline

## 1.2.0

### Minor Changes

- [#135](https://github.com/electron-userland/electron-builder-binaries/pull/135) [`a9d7692`](https://github.com/electron-userland/electron-builder-binaries/commit/a9d7692c6c68607368b2596d765bc867d0cc2d2a) Thanks [@BarakXYZ](https://github.com/BarakXYZ)! - feat: update dmgbuild to include size and shrink options

## 1.1.0

### Minor Changes

- [#127](https://github.com/electron-userland/electron-builder-binaries/pull/127) [`9232590`](https://github.com/electron-userland/electron-builder-binaries/commit/9232590fb3ebc28546309cccfde34a866f2126af) Thanks [@mmaietta](https://github.com/mmaietta)! - feat: adding badge_icons support via optional dependency

## 1.0.1

### Patch Changes

- [#122](https://github.com/electron-userland/electron-builder-binaries/pull/122) [`113434a`](https://github.com/electron-userland/electron-builder-binaries/commit/113434a46cd4c65af51474c978e2fef1c3227d02) Thanks [@mmaietta](https://github.com/mmaietta)! - chore: redeploy same version

## 1.0.0

### Major Changes

- [#118](https://github.com/electron-userland/electron-builder-binaries/pull/118) [`fe38646`](https://github.com/electron-userland/electron-builder-binaries/commit/fe38646ff005f270eaa75d6fff179bdeb43d63dd) Thanks [@mmaietta](https://github.com/mmaietta)! - feat: adding dmgbuild v1.6.7 toolset w/ portable python v3.14.2
