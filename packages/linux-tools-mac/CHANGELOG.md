# linux-tools-mac

## 1.0.1

### Patch Changes

- [#224](https://github.com/electron-userland/electron-builder-binaries/pull/224) [`24c67bd`](https://github.com/electron-userland/electron-builder-binaries/commit/24c67bd464af5924bbe4e9db8d89bf311e29e457) Thanks [@claude](https://github.com/apps/claude)! - fix: rebuild the macOS bundle on macos-15 runners (with Xcode 26 selected) so the bundled Homebrew binaries (gtar, lzip, glib, gettext, etc.) run on macOS 15+, instead of aborting with "built for macOS 26.0 which is newer than running OS" on hosts older than macOS 26 (electron-userland/electron-builder#10084)

## 1.0.0

### Major Changes

- [#168](https://github.com/electron-userland/electron-builder-binaries/pull/168) [`ae65f01`](https://github.com/electron-userland/electron-builder-binaries/commit/ae65f01263ba4d3bf75ec89f5c7c3ad40e3b216b) Thanks [@mmaietta](https://github.com/mmaietta)! - feat: upgrade linux-tools-mac to latest toolsets of gnu-tar, lzip, makedepend, glib, libgsf, libtool, pcre, gettext, binutils
