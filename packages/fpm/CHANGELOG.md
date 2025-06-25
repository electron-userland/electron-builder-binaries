# fpm

## 2.0.1

### Patch Changes

- [#74](https://github.com/electron-userland/electron-builder-binaries/pull/74) [`4e87907`](https://github.com/electron-userland/electron-builder-binaries/commit/4e87907892868c35814a7e5566362f2375422b87) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(fpm): downgrade docker image to debian:buster to support older distros

## 2.0.0

### Major Changes

- [#65](https://github.com/electron-userland/electron-builder-binaries/pull/65) [`f580acf`](https://github.com/electron-userland/electron-builder-binaries/commit/f580acf1ad72dd2b95540476b258e20a0dd8380a) Thanks [@mmaietta](https://github.com/mmaietta)! - chore(fpm): upgrade to multi-arch docker/darwin builds of fpm 1.16.0 with ruby 3.4.3

### Minor Changes

- [#68](https://github.com/electron-userland/electron-builder-binaries/pull/68) [`2cb21af`](https://github.com/electron-userland/electron-builder-binaries/commit/2cb21afab7a47542b367923f4ddfea998f4c8bbd) Thanks [@mmaietta](https://github.com/mmaietta)! - feat: add arm64 to fpm binary releases

### Patch Changes

- [#69](https://github.com/electron-userland/electron-builder-binaries/pull/69) [`a6a781c`](https://github.com/electron-userland/electron-builder-binaries/commit/a6a781cc8a8b78e0fa257a71adef920d5fce53c6) Thanks [@mmaietta](https://github.com/mmaietta)! - fix: remove / from TARGET_ARCH when creating archive (to prevent OS interpretation of it being a directory)

## 1.0.0

### Major Changes

- [#61](https://github.com/electron-userland/electron-builder-binaries/pull/61) [`f8bb93d`](https://github.com/electron-userland/electron-builder-binaries/commit/f8bb93d87215fe9095c419e2939f3ea1bc60fefa) Thanks [@mmaietta](https://github.com/mmaietta)! - chore(deploy): deploy v1 (re-release of previous artifact) under new monorepo setup
