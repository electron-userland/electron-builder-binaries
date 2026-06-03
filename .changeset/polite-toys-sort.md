---
"wine": patch
---

fix(wine): Added `patchelf --set-rpath '$ORIGIN/../lib'` block for Linux ELF binaries to make toolset fully self-contained
