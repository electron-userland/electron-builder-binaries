---
"dmg-builder": patch
---

fix(dmg-builder): CJK license encoding in DMG builds: re-bundle CJK codec extensions, correct the `multibyte_encoding` → `multibyte` key-name bug in `licensing.py`, and add UTF-8 fallbacks so a missing codec never aborts the build.
