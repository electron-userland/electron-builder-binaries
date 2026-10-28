---
"rpm": major
---

feat(rpm): introducing new portable `rpm` toolset (rpmbuild 6.1.0) for linux-amd64, linux-arm64v8 and darwin-arm64. Relocatable, ignores host `/etc/rpm` and `~/.rpmmacros`, and pins `%_rpmformat 4` and `%_build_id_links none` so electron-builder's rpm output is identical across build hosts and installable by rpm 4.x (electron-userland/electron-builder#10471)
