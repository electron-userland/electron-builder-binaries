---
"archive": major
---

feat(archive): introducing the `archive` toolset, which consolidates the `rpm` and `linux-tools-mac` toolsets (and the xz electron-builder needs for fpm) into one bundle per platform: linux-amd64, linux-arm64v8, linux-i386, darwin-arm64 and darwin-x86_64. Its `bin/` (put first on PATH for fpm) holds xz, lzip, GNU tar (`tar`, `gtar`), GNU ar (`ar`, `gar`, deterministic by default) and bsdtar, plus rpm/rpmbuild 6.1.0 (the rpm@1.0.0 build) on linux-amd64, linux-arm64v8 and darwin-arm64. Every tool is built in CI from its upstream release, pinned by sha256 and checked against the upstream OpenPGP signature, and is self-contained (C library only on Linux, macOS system libraries only and macOS 15+ on macOS). The `rpm` and `linux-tools-mac` packages are retired; their published releases stay available.
