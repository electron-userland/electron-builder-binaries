# electron-builder-binaries

[electron-builder](http://github.com/electron-userland/electron-builder) downloads required tools files on demand (e.g. to code sign windows application, to make AppX).

Version and SHA512 checksum of binary is hardcoded in the electron-builder code. So, even if this repository will be compromised, users are not affected.