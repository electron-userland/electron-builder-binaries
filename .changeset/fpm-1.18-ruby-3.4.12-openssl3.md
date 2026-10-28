---
"fpm": minor
---

feat(fpm): update fpm from 1.17.0 to 1.18.0 and the bundled Ruby from 3.4.3 to 3.4.12, and replace Debian buster's end-of-life OpenSSL 1.1.1n with OpenSSL 3.5.9 (LTS) built from source and linked statically into Ruby on Linux. fpm 1.18.0 fixes corrupted `.deb` files when the `ar` fallback runs with Xcode 26.4+'s Apple `ar`. Linux builds stay on the buster image, so the glibc floor is unchanged (GLIBC_2.28), and the bundles no longer ship `libssl.so.1.1`/`libcrypto.so.1.1`. The build now fails if Ruby's openssl extension does not report OpenSSL 3.x, if a Linux bundle needs a glibc newer than 2.28, or if the bundled fpm cannot build a `.deb`. Archive names change to `fpm-1.18.0-ruby-3.4.12-<os>-<arch>.7z`, and each bundle includes the OpenSSL license.
