---
"linux-tools-mac": minor
---

feat: trim the macOS bundle to the tools electron-builder and fpm actually run (gtar, lzip, binutils `ar`, with `gar` kept as a symlink to `ar`) plus their dylibs, dropping glib, gettext, libgsf, libtool, pcre and makedepend. Picks up binutils 2.47 from Homebrew. The build now fails unless every bundled binary and dylib resolves its non-system dylibs inside the bundle, requires macOS 15.0 or older, and is validly signed, and the tests exercise the same gtar/ar/lzip invocations fpm and electron-builder use
