# fpm

## 2.1.4

### Patch Changes

- [#97](https://github.com/electron-userland/electron-builder-binaries/pull/97) [`d2bf129`](https://github.com/electron-userland/electron-builder-binaries/commit/d2bf1296a432217e31ba3c6f6391d797431b9251) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(fpm): codesign to prevent process killed on macos

## 2.1.3

### Patch Changes

- [#95](https://github.com/electron-userland/electron-builder-binaries/pull/95) [`b77f554`](https://github.com/electron-userland/electron-builder-binaries/commit/b77f554271ec9ef77255b389ad13c24feabc02ec) Thanks [@mmaietta](https://github.com/mmaietta)! - chore(deploy): redeploy same version of fpm

## 2.1.2

### Patch Changes

- [#93](https://github.com/electron-userland/electron-builder-binaries/pull/93) [`26f2474`](https://github.com/electron-userland/electron-builder-binaries/commit/26f2474b9908f9159d27db047fb649f8613a6bc6) Thanks [@mmaietta](https://github.com/mmaietta)! - chore: bump fpm version again for redeploy

## 2.1.1

### Patch Changes

- [#91](https://github.com/electron-userland/electron-builder-binaries/pull/91) [`484e835`](https://github.com/electron-userland/electron-builder-binaries/commit/484e8358b2135abdc895f62ef9914d9f059c98fe) Thanks [@mmaietta](https://github.com/mmaietta)! - chore: retrigger fpm release

## 2.1.0

### Minor Changes

- [#79](https://github.com/electron-userland/electron-builder-binaries/pull/79) [`cdcdc3e`](https://github.com/electron-userland/electron-builder-binaries/commit/cdcdc3e1f34cc43491b427377ae87ce552d42ba3) Thanks [@mmaietta](https://github.com/mmaietta)! - chore(fpm): updating fpm to 1.17.0

### Patch Changes

- [#82](https://github.com/electron-userland/electron-builder-binaries/pull/82) [`97760e2`](https://github.com/electron-userland/electron-builder-binaries/commit/97760e2a1456f5745d2cd3b125600a3dd7f694bc) Thanks [@mmaietta](https://github.com/mmaietta)! - fix: resolving library import paths with RUBY_HOME and RUBYLIB

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
