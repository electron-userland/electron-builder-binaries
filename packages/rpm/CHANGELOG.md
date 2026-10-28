# rpm

## 1.0.0

### Major Changes

- [#238](https://github.com/electron-userland/electron-builder-binaries/pull/238) [`96e2c1d`](https://github.com/electron-userland/electron-builder-binaries/commit/96e2c1d276bc16200188ef754c2b9436577198df) Thanks [@claude](https://github.com/apps/claude)! - feat(rpm): introducing new portable `rpm` toolset (rpmbuild 6.1.0) for linux-amd64, linux-arm64v8 and darwin-arm64. Relocatable, ignores host `/etc/rpm` and `~/.rpmmacros`, and pins `%_rpmformat 4` and `%_build_id_links none` so electron-builder's rpm output is identical across build hosts and installable by rpm 4.x (electron-userland/electron-builder#10471)
