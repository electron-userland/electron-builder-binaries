---
"win-codesign": patch
---

fix(win-codesign): bundle the full Microsoft.Trusted.Signing.Client `bin/<arch>` payload, pin the nupkg SHA-256 (fail-closed verification by default) and stop copying x64 ATS DLLs into the arm64 kit directory
