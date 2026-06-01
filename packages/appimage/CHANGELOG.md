# appimage

## 1.1.0

### Minor Changes

- [#161](https://github.com/electron-userland/electron-builder-binaries/pull/161) [`bbd7eaa`](https://github.com/electron-userland/electron-builder-binaries/commit/bbd7eaa40b74af43b0488fb34870ffb78aaed9fa) Thanks [@mmaietta](https://github.com/mmaietta)! - feat(appimage): add unsquashfs to the toolset

### Patch Changes

- [#156](https://github.com/electron-userland/electron-builder-binaries/pull/156) [`4f378ce`](https://github.com/electron-userland/electron-builder-binaries/commit/4f378cecc124b3c0424007da9b62aaf52854a8d2) Thanks [@mmaietta](https://github.com/mmaietta)! - chore: updating scripts w/ positional args, checksum matches, and general hardening

- [#152](https://github.com/electron-userland/electron-builder-binaries/pull/152) [`d1f6262`](https://github.com/electron-userland/electron-builder-binaries/commit/d1f6262334fc1aba5a1b59a36fecd9d174ea28e4) Thanks [@mmaietta](https://github.com/mmaietta)! - chore: embedding LICENSE/COPYING files within each toolset bundle

- [#150](https://github.com/electron-userland/electron-builder-binaries/pull/150) [`661c1f4`](https://github.com/electron-userland/electron-builder-binaries/commit/661c1f41d88b9083b78249a9d1b1da30c0af609c) Thanks [@Tomurisk](https://github.com/Tomurisk)! - chore: use apt-get download of i386 libs for appimage toolset

- [#163](https://github.com/electron-userland/electron-builder-binaries/pull/163) [`7d25bb7`](https://github.com/electron-userland/electron-builder-binaries/commit/7d25bb711dbc6ae33545618de7860952708debc1) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(appimage): incorrect RPATH for portability

- [#157](https://github.com/electron-userland/electron-builder-binaries/pull/157) [`fe95835`](https://github.com/electron-userland/electron-builder-binaries/commit/fe958350377024c7421659fa5c364eff86fa043c) Thanks [@Tomurisk](https://github.com/Tomurisk)! - chore: replace x86_64 archive with i386 when TARGETARCH i386

## 1.0.3

### Patch Changes

- [#143](https://github.com/electron-userland/electron-builder-binaries/pull/143) [`c81095a`](https://github.com/electron-userland/electron-builder-binaries/commit/c81095a0976e0690975871dce744e0b27b74546a) Thanks [@sabonerune](https://github.com/sabonerune)! - fix(appimage): exclude libm from AppImage build process

## 1.0.2

### Patch Changes

- [#109](https://github.com/electron-userland/electron-builder-binaries/pull/109) [`6858c94`](https://github.com/electron-userland/electron-builder-binaries/commit/6858c945046b5034395bdac48cbdf9458ba70aa0) Thanks [@mmaietta](https://github.com/mmaietta)! - fix: compile mksquashfs and desktop-file-validate for mac from source and copy needed dylibs

- [#117](https://github.com/electron-userland/electron-builder-binaries/pull/117) [`6cde90e`](https://github.com/electron-userland/electron-builder-binaries/commit/6cde90e200abbb42016af02c2322650994d25465) Thanks [@mmaietta](https://github.com/mmaietta)! - fix(appimage): auto remove quarantine bit on mac when executing via wrapper script

## 1.0.1

### Patch Changes

- [#105](https://github.com/electron-userland/electron-builder-binaries/pull/105) [`c9d3b67`](https://github.com/electron-userland/electron-builder-binaries/commit/c9d3b676ffb8ad21f2278e7b742dcb4e53eb23d1) Thanks [@mmaietta](https://github.com/mmaietta)! - chore(appimage): redeploy full bundle

## 1.0.0

### Major Changes

- [#103](https://github.com/electron-userland/electron-builder-binaries/pull/103) [`02d5141`](https://github.com/electron-userland/electron-builder-binaries/commit/02d514185f10660a0ba651ad1af821c017a32ab1) Thanks [@mmaietta](https://github.com/mmaietta)! - chore(appimage): upgrading runtime to 20251108 and related toolsets for mac/linux per-arch
