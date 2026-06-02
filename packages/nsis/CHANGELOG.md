# nsis

## 2.0.0

### Major Changes

- [#176](https://github.com/electron-userland/electron-builder-binaries/pull/176) [`7f22e69`](https://github.com/electron-userland/electron-builder-binaries/commit/7f22e6993d7a06d76094cafb22a355343c4c356e) Thanks [@mmaietta](https://github.com/mmaietta)! - feat(nsis): compiling windows `makensis` (with LOG and STRLENGTH enabled) from source

## 1.2.1

### Patch Changes

- [#177](https://github.com/electron-userland/electron-builder-binaries/pull/177) [`736238b`](https://github.com/electron-userland/electron-builder-binaries/commit/736238b93da99a135906d815bdec4313b6dbae99) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(nsis): properly copy `nsProcess.dll`/`nsProcessW.dll` to both Plugin directories and add to sanity test script

## 1.2.0

### Minor Changes

- [#170](https://github.com/electron-userland/electron-builder-binaries/pull/170) [`b6fae60`](https://github.com/electron-userland/electron-builder-binaries/commit/b6fae60266ac44d141c31af84426b25931dffaea) Thanks [@mmaietta](https://github.com/mmaietta)! - feat(nsis): compile elevate.exe from source

- [#175](https://github.com/electron-userland/electron-builder-binaries/pull/175) [`cbfac2b`](https://github.com/electron-userland/electron-builder-binaries/commit/cbfac2b6fa296c24af5cf1d8dc4ac1f398144e74) Thanks [@mmaietta](https://github.com/mmaietta)! - feat(nsis): adding compilation of linux arm64 `makensis` binary

### Patch Changes

- [#167](https://github.com/electron-userland/electron-builder-binaries/pull/167) [`6b8195a`](https://github.com/electron-userland/electron-builder-binaries/commit/6b8195a4a1c1e468d2952566ee04f7a00d57b94d) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(nsis): validate plugin DLL PE headers and add compile smoke test for all 16 built-in plugins

- [#174](https://github.com/electron-userland/electron-builder-binaries/pull/174) [`45a1dcb`](https://github.com/electron-userland/electron-builder-binaries/commit/45a1dcb9c7059fa86350e64c1165246e289dd0ed) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(nsis): clean up nsis-lang-fixes to only the strings that need to be injected (not full file replace)

- [#174](https://github.com/electron-userland/electron-builder-binaries/pull/174) [`45a1dcb`](https://github.com/electron-userland/electron-builder-binaries/commit/45a1dcb9c7059fa86350e64c1165246e289dd0ed) Thanks [@mmaietta](https://github.com/mmaietta)! - chore(nsis): cleaning up legacy entrypoint that requires manual NSISDIR configuration

## 1.1.0

### Minor Changes

- [#159](https://github.com/electron-userland/electron-builder-binaries/pull/159) [`7c8f60a`](https://github.com/electron-userland/electron-builder-binaries/commit/7c8f60a213b73ec467af263d34ce27b7dc1fa8c9) Thanks [@skmedix](https://github.com/skmedix)! - feat(nsis): upgrade nsis to 3.12

- [#162](https://github.com/electron-userland/electron-builder-binaries/pull/162) [`5a69752`](https://github.com/electron-userland/electron-builder-binaries/commit/5a69752978c055a793578ce61164acfc8f921a7d) Thanks [@skmedix](https://github.com/skmedix)! - feat(nsis): upgrade INetC plugin to 1.0.5.7

### Patch Changes

- [#156](https://github.com/electron-userland/electron-builder-binaries/pull/156) [`4f378ce`](https://github.com/electron-userland/electron-builder-binaries/commit/4f378cecc124b3c0424007da9b62aaf52854a8d2) Thanks [@mmaietta](https://github.com/mmaietta)! - chore: updating scripts w/ positional args, checksum matches, and general hardening

- [#152](https://github.com/electron-userland/electron-builder-binaries/pull/152) [`d1f6262`](https://github.com/electron-userland/electron-builder-binaries/commit/d1f6262334fc1aba5a1b59a36fecd9d174ea28e4) Thanks [@mmaietta](https://github.com/mmaietta)! - chore: embedding LICENSE/COPYING files within each toolset bundle

- [#164](https://github.com/electron-userland/electron-builder-binaries/pull/164) [`facb8b5`](https://github.com/electron-userland/electron-builder-binaries/commit/facb8b54a1c766bec5b949b7a925a7bb3d8c3304) Thanks [@mmaietta](https://github.com/mmaietta)! - chore(nsis): update base git url of nsis GH repo. Resolve translation file FIXMEs

## 1.0.0

### Major Changes

- [#78](https://github.com/electron-userland/electron-builder-binaries/pull/78) [`54c1b58`](https://github.com/electron-userland/electron-builder-binaries/commit/54c1b58aa91247cd6dd85a0632db7a5eb92fec7c) Thanks [@mmaietta](https://github.com/mmaietta)! - chore: upgrading makensis to 3.11

### Minor Changes

- [#131](https://github.com/electron-userland/electron-builder-binaries/pull/131) [`bd4ca86`](https://github.com/electron-userland/electron-builder-binaries/commit/bd4ca86e06bffc943f16bb0a83112383754fe0be) Thanks [@mmaietta](https://github.com/mmaietta)! - feat(nsis): add additional plugins back from nsis-resources
