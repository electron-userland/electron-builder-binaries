---
"nsis": patch
---

fix(nsis): ship the Unicode build of `nsisunz.dll` in `Plugins/x86-unicode`. In nsis@2.0.3 the ANSI build from `Nsisunz.zip` was installed after the Unicode build from `NSISunzU.zip` and overwrote it, so `x86-unicode/nsisunz.dll` was byte-identical to `x86-ansi/nsisunz.dll` and Unicode installers (the NSIS default) loaded an ANSI plugin. `Nsisunz.zip` now only installs to `x86-ansi`, and the build and test suite fail unless `x86-unicode/nsisunz.dll` differs from the ANSI one and imports the wide-char API (`CreateDirectoryW`) while the ANSI one imports `CreateDirectoryA`.
