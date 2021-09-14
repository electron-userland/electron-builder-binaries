# go get -u github.com/go-bindata/go-bindata/go-bindata (pack not used because cannot properly select dir to generate and no way to specify explicitly)

.PHONY: update-appimage-runtime winCodeSign

update-appimage-runtime:
	curl -L https://github.com/AppImage/AppImageKit/releases/download/13/runtime-x86_64 -o AppImage/runtime-x64
	curl -L https://github.com/AppImage/AppImageKit/releases/download/13/runtime-i686 -o AppImage/runtime-ia32
	curl -L https://github.com/AppImage/AppImageKit/releases/download/13/runtime-aarch64 -o AppImage/runtime-arm64
	curl -L https://github.com/AppImage/AppImageKit/releases/download/13/runtime-armhf -o AppImage/runtime-armv7l

publish-appimage:
	NAME=appimage VERSION=13.0.0 ./publish.sh

update-zstd:
	./scripts/update-zstd.sh

publish-zstd:
	NAME=zstd VERSION=1.5.0 ./publish-m.sh

publish-nsis:
	NAME=nsis VERSION=3.0.4.2 ./publish.sh

publish-nsis-resources:
	NAME=nsis-resources VERSION=3.4.1 ./publish.sh

publish-winCodeSign:
	NAME=winCodeSign VERSION=2.6.0 ./publish.sh

publish-wine-mac:
	./publish-wine-mac.sh

download-nsis-plugins:
	./scripts/nsis-plugins.sh