---
"dmg-builder": patch
---

fix(dmg-builder): make the macOS 11.0 floor real and enforce it. The post-build check in `build.sh` scanned the output folder, which only holds the tarball, so it never inspected a binary; it now extracts each shipped archive and fails on any Mach-O that links a Homebrew library or has a `minos` newer than `MACOSX_DEPLOYMENT_TARGET`, and on an archive with no Mach-O files at all. CI self-tests the check against fixtures before building.
