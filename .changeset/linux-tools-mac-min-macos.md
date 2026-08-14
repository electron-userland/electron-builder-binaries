---
"linux-tools-mac": patch
---

fix: rebuild the macOS bundle on macos-15 runners (with Xcode 26 selected) so the bundled Homebrew binaries (gtar, lzip, glib, gettext, etc.) run on macOS 15+, instead of aborting with "built for macOS 26.0 which is newer than running OS" on hosts older than macOS 26 (electron-userland/electron-builder#10084)
