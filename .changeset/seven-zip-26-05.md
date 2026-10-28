---
"7zip": minor
---

feat(7zip): update bundled 7-Zip from 24.09 to 26.05

All platform bundles now ship 7-Zip 26.05 (released 2026-10-21), picking up upstream security fixes missing from 24.09, including CVE-2025-11001 / CVE-2025-11002 (ZIP symlink path traversal), CVE-2025-55188 (symlink handling) and CVE-2026-14266 (XZ decoder heap overflow). The pinned SHA-256 values for the upstream downloads are updated to match the official 26.05 release assets at github.com/ip7z/7zip.
