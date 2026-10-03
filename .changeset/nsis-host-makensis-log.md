---
"nsis": patch
---

fix(nsis): build the Linux and macOS `makensis` with `NSIS_CONFIG_LOG=yes` to match the log-enabled Windows stubs shipped since 2.0.0. With the flag off, the host compilers rejected `LogSet`/`LogText` and numbered every opcode after `EW_LOG` one lower than the stubs expect, so `LockWindow` (used by MUI2), `SectionGetFlags`/`SectionSetFlags` and friends were emitted as the wrong instructions in installers cross-compiled on Linux or macOS.
