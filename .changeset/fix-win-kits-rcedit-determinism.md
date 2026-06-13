---
"win-codesign": patch
---

fix(win-codesign): add `--target` flag to build.sh and run kits/ats/rcedit on a dedicated x64 CI runner so arch-agnostic artifacts are produced exactly once, eliminating the race where the arm64 matrix job could overwrite the x64 job's identical outputs
