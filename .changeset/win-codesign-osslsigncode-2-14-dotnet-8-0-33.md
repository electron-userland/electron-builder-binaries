---
"win-codesign": patch
---

fix(win-codesign): update `osslsigncode` from 2.11 to 2.14 on all platforms and the bundled .NET runtime (used by Azure Trusted Signing under Wine) from 8.0.28 to 8.0.33. osslsigncode 2.12 fixes CVE-2026-39853 (buffer overflow while extracting message digests during `verify`), 2.13 fixes integer overflows and double frees in APPX processing and memory corruption in PE page hash computation (CVE-2026-39855, CVE-2026-39856), and 2.14 fixes an APPX memory leak; the `sign` options electron-builder passes are unchanged (2.14 only drops the verification options from `attach-signature`). .NET 8.0.29 through 8.0.33 are all security releases. The .NET asset is renamed accordingly, from `dotnet-runtime-win-x64-8_0_28.zip` to `dotnet-runtime-win-x64-8_0_33.zip`. The stale `2.9` defaults in the per-platform build scripts and the Linux Dockerfile now match the 2.14 default used by CI
