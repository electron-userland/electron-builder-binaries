# wine

## 1.0.1

### Patch Changes

- [#197](https://github.com/electron-userland/electron-builder-binaries/pull/197) [`f1089f6`](https://github.com/electron-userland/electron-builder-binaries/commit/f1089f6483aa1128e2ede4d79e091b1c5204b781) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(wine): Added `patchelf --set-rpath '$ORIGIN/../lib'` block for Linux ELF binaries to make toolset fully self-contained

## 1.0.0

### Major Changes

- [#134](https://github.com/electron-userland/electron-builder-binaries/pull/134) [`79a7165`](https://github.com/electron-userland/electron-builder-binaries/commit/79a7165b8ef95505e35d54d25a644bb3af4752e4) Thanks [@mmaietta](https://github.com/mmaietta)! - feat: update wine to latest 11.0

### Patch Changes

- [#193](https://github.com/electron-userland/electron-builder-binaries/pull/193) [`5dfd9d9`](https://github.com/electron-userland/electron-builder-binaries/commit/5dfd9d91c055f3db7fca60019233130208602178) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(wine): fix pruning of unneeded wine files to dramatically reduce artifact size
