---
"appimage": minor
---

feat(appimage): build squashfs-tools 4.7.5 (plus upstream macOS-build and duplicate-detection race fixes) against a pinned, checksum-verified static zstd 1.5.7 so Linux and macOS hosts produce byte-identical zstd images, default `mksquashfs` to zstd, round-trip test every compressor at build time, bundle the remaining Homebrew dylib dependencies on macOS (incl. the missing `libjpeg`), add an `unsquashfs` entrypoint and GPG-verify the type2-runtime downloads
