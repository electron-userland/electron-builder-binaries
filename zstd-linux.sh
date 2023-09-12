#!/usr/bin/env bash
set -ex

# shellcheck disable=SC2046
eval $(minikube -p minikube docker-env)

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cidFile="/tmp/zstd-build-container-id"
if test -f "$cidFile"; then
  echo "already running (remove $cidFile)"
  exit 1
fi

cd "$BASEDIR"
docker run --cidfile="$cidFile" buildpack-deps:bionic bash -c \
'git clone --depth 1 --branch v1.5.0 https://github.com/facebook/zstd.git && cd zstd && make -j5 install && cd .. &&
 git clone --depth 1 --branch 4.5 https://github.com/plougher/squashfs-tools && cd squashfs-tools/squashfs-tools &&
 apt-get update -y && apt-get install -y liblzo2-dev && make -j5 XZ_SUPPORT=1 LZO_SUPPORT=1 ZSTD_SUPPORT=1 GZIP_SUPPORT=0 COMP_DEFAULT=zstd install &&
 cp /usr/local/bin/mksquashfs /tmp/mksquashfs-64
 '

containerId=$(cat "$cidFile")
docker cp "$containerId":/usr/local/bin/zstd zstd/linux-x64/zstd
docker cp "$containerId":/tmp/mksquashfs-64 AppImage/linux-x64/mksquashfs
docker cp "$containerId":/tmp/mksquashfs-32 AppImage/linux-ia32/mksquashfs
docker rm "$containerId"
unlink "$cidFile"
