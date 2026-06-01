# dmg-builder

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
