---
"squirrel.windows": minor
---

feat(squirrel.windows): bundle a pinned, checksum-verified 7-Zip 26.05 (x64 and arm64) and nuget.exe 7.9.0

The vendored `7z.exe`/`7z.dll` were previously copied from whatever 7-Zip the build runner had installed (26.01 in 1.1.1). They now come from the official 7-Zip 26.05 installers at github.com/ip7z/7zip, verified against pinned SHA-256 values, with the FileVersion and PE architecture checked at build time. This picks up the 26.02 XZ decoder fix (CVE-2026-14266) and later upstream fixes. The bundle keeps the same layout (`7z.exe`, `7z.dll`, `7z-x64.exe`, `7z-x64.dll`, `7z-LICENSE.txt`) and adds native `7z-arm64.exe`/`7z-arm64.dll`, which electron-builder selects on arm64 Windows hosts. The pinned standalone `nuget.exe` moves from 6.14.0 to 7.9.0.
