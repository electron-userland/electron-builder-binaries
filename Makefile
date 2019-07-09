# go get -u github.com/go-bindata/go-bindata/go-bindata (pack not used because cannot properly select dir to generate and no way to specify explicitly)

.PHONY: update-appimage-runtime winCodeSign

update-appimage-runtime:
	curl -L https://github.com/AppImage/AppImageKit/releases/download/12/runtime-x86_64 -o AppImage/runtime-x64
	curl -L https://github.com/AppImage/AppImageKit/releases/download/12/runtime-i686 -o AppImage/runtime-ia32
	curl -L https://github.com/AppImage/AppImageKit/releases/download/12/runtime-aarch64 -o AppImage/runtime-arm64
	curl -L https://github.com/AppImage/AppImageKit/releases/download/12/runtime-armhf -o AppImage/runtime-armv7l

publish-appimage:
	NAME=appimage VERSION=12.0.0 ./publish.sh

winCodeSign:
	NAME=winCodeSign VERSION=2.4.1 ./publish.sh

publish-wine-mac:
	./publish-wine-mac.sh