---
"appimage": patch
---

fix(appimage): ship the license of every bundled component (squashfs-tools with a modification notice, desktop-file-utils, OpenJPEG, zstd, every Ubuntu/Homebrew library copied into the bundle, and libfuse, squashfuse, musl, zstd, zlib and mimalloc inside the type2-runtime) in `LICENSES/<component>/`, map every binary to them in `LICENSES/MANIFEST.tsv`, list the exact sources in `LICENSES/SOURCES.md`, and fail the build when a binary has no license
