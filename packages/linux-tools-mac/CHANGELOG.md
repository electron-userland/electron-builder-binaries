# linux-tools-mac

## 1.1.0

### Minor Changes

- [#243](https://github.com/electron-userland/electron-builder-binaries/pull/243) [`b00e099`](https://github.com/electron-userland/electron-builder-binaries/commit/b00e0999aa3055f4cafc6b500e85b7897e6da578) Thanks [@claude](https://github.com/apps/claude)! - feat: trim the macOS bundle to the tools electron-builder and fpm actually run (gtar, lzip, binutils `ar`, with `gar` kept as a symlink to `ar`) plus their dylibs, dropping glib, gettext, libgsf, libtool, pcre and makedepend. Picks up binutils 2.47 from Homebrew. The build now fails unless every bundled binary and dylib resolves its non-system dylibs inside the bundle, requires macOS 15.0 or older, and is validly signed, and the tests exercise the same gtar/ar/lzip invocations fpm and electron-builder use

## 1.0.1

### Patch Changes

- [#224](https://github.com/electron-userland/electron-builder-binaries/pull/224) [`24c67bd`](https://github.com/electron-userland/electron-builder-binaries/commit/24c67bd464af5924bbe4e9db8d89bf311e29e457) Thanks [@claude](https://github.com/apps/claude)! - fix: rebuild the macOS bundle on macos-15 runners (with Xcode 26 selected) so the bundled Homebrew binaries (gtar, lzip, glib, gettext, etc.) run on macOS 15+, instead of aborting with "built for macOS 26.0 which is newer than running OS" on hosts older than macOS 26 (electron-userland/electron-builder#10084)

## 1.0.0

### Major Changes

- [#168](https://github.com/electron-userland/electron-builder-binaries/pull/168) [`ae65f01`](https://github.com/electron-userland/electron-builder-binaries/commit/ae65f01263ba4d3bf75ec89f5c7c3ad40e3b216b) Thanks [@mmaietta](https://github.com/mmaietta)! - feat: upgrade linux-tools-mac to latest toolsets of gnu-tar, lzip, makedepend, glib, libgsf, libtool, pcre, gettext, binutils
