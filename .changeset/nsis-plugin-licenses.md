---
"nsis": patch
---

fix(nsis): ship the license terms of every bundled community plugin and of `elevate.exe` in `LICENSES/`. Until now the plugin build kept only the DLLs and headers of each download and dropped its license files (StdUtils' `LGPL.txt` among them), so only NSIS's own `LICENSE` shipped. Each plugin's license / readme files are now copied from its download to `LICENSES/<plugin>/`, INetC's and StdUtils' licenses (plus the RHash and BLAKE2 licenses of code StdUtils compiles in) are pinned by SHA256 from their source repositories at the bundled versions, `LICENSES/plugin-dlls.tsv` records which plugin each DLL came from, and the build and test suite fail when a plugin DLL has no license terms.
