---
"fpm": minor
---

feat(fpm): ship native tools in the toolset's root `bin/`: a portable `xz` CLI (XZ Utils 5.8.4, liblzma linked statically) on every platform, and the relocatable `rpm`/`rpmbuild` (rpm 6.1.0, the same build as the `rpm` toolset) on linux-amd64, linux-arm64v8 and darwin-arm64. Putting `bin/` on PATH lets fpm build deb, pacman, freebsd and rpm packages without a host xz or rpmbuild. Licenses for both are in `LICENSES/`.
