---
"nsis": patch
---

fix(nsis): strip unused `Bin/` tools (`RegTool-*.bin`, `makensisw.exe`, `zip2exe.exe`, `MakeLangId.exe`) from the bundle. `makensis.exe` lives at `windows/makensis.exe` and reads none of these during compilation; `RegTool-*.bin` and `makensisw.exe` are recurring AV false-positives.
