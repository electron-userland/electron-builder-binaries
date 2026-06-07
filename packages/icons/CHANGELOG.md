# icons

## 1.1.0

### Minor Changes

- [#204](https://github.com/electron-userland/electron-builder-binaries/pull/204) [`b96a825`](https://github.com/electron-userland/electron-builder-binaries/commit/b96a825027325023d955f96a3f1d8eb9b5ea112e) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(icons): replace png2icons with wasm-vips Lanczos3 resampling for high-quality icon conversion

## 1.0.1

### Patch Changes

- [#186](https://github.com/electron-userland/electron-builder-binaries/pull/186) [`a568ac2`](https://github.com/electron-userland/electron-builder-binaries/commit/a568ac27c711b40be9b0f77222add8ef8e7cdf65) Thanks [@mmaietta](https://github.com/mmaietta)! - chore(deploy): redeploying due to failed attest CJS->ESM module update

## 1.0.0

### Major Changes

- [#183](https://github.com/electron-userland/electron-builder-binaries/pull/183) [`db378ba`](https://github.com/electron-userland/electron-builder-binaries/commit/db378baff88005fc74462b224c9a3c27e3606771) Thanks [@mmaietta](https://github.com/mmaietta)! - feat(icons): new `packages/icons` portable icon conversion toolset that accepts `.png`, `.svg`, `.icns` and can output `icns` (macOS), `ico` (Windows), `set` (Linux PNG set at 16/24/32/48/64/128/256/512 px)
