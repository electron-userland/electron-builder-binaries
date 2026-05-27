# feat(nsis): compile Windows `makensis` (with LOG and STRLEN=8192) from source

## Summary

Replaces the two-step SourceForge download (official NSIS 3.12 + separate `strlen_8192`
patch zip) with a fully source-compiled Windows bundle. `makensis.exe` **and all installer
stubs** are now built from the NSIS 3.12 source tree using Docker + MinGW-w64
cross-compilation on a standard Ubuntu runner, with consistent build flags applied to every
component: `NSIS_CONFIG_LOG=yes` and `NSIS_MAX_STRLEN=8192`.

The plugin set, NSIS version, and bundle layout are unchanged.

---

## What Changed

### `packages/nsis/assets/nsis-windows.sh` *(complete rewrite)*

**Before:** Downloaded `nsis-3.12.zip` from SourceForge (SHA-256 verified), then downloaded
`nsis-3.12-strlen_8192.zip` (SHA-256 verified), and applied the patch by overlaying the
patched `makensis.exe` / `makensisw.exe` from the strlen zip over the base install.

**After:** Builds from source in a Docker container:

1. **Dockerfile** written inline and built at runtime using `docker build`. The image:
   - Installs the MinGW-w64 cross-toolchain (`gcc-mingw-w64-i686`, `g++-mingw-w64-i686`,
     `libz-mingw-w64-dev`, `nasm`, `scons`)
   - Clones NSIS 3.12 using `git init` + `git fetch --depth=1` (supports both branch names
     and commit SHAs, unlike `git clone --branch`)
   - Applies a one-line patch to `Source/build.cpp`: replaces a `FIELD_OFFSET` call that
     uses a runtime `wcslen()` result (rejected by MinGW-w64's strict `__builtin_offsetof`)
     with an equivalent `offsetof` + runtime arithmetic expression
   - Builds a **native** `halibut` binary from the NSIS-bundled sources (the apt package is
     too old for NSIS v3.12's `.but` doc syntax); wraps `i686-w64-mingw32-gcc` to intercept
     the halibut link step and redirect it to this native binary
   - Wraps `i686-w64-mingw32-g++` to: add `-static-libgcc -static-libstdc++` on link steps
     (avoids runtime DLL dependency on `libgcc_s_dw2-1.dll` / `libstdc++-6.dll`), and create
     a no-extension copy alongside the `.exe` (SCons names link targets without extension on
     Linux; the MinGW linker auto-appends `.exe`)
   - Removes `libz.dll.a` so the linker falls back to static `libz.a` (avoids a `zlib1.dll`
     runtime dependency absent on stock Windows)
   - Runs `scons` targeting `install` with:
     `CC=i686-w64-mingw32-gcc`, `CXX=i686-w64-mingw32-g++`, `SKIPUTILS="NSIS Menu"`,
     `NSIS_CONFIG_CONST_DATA_PATH=no`, `NSIS_CONFIG_LOG=yes`, `NSIS_MAX_STRLEN=8192`,
     `ZLIB_W32=/usr/i686-w64-mingw32`
   - Installer stubs (`Stubs/bzip2-x86-*`, `lzma-x86-*`, `zlib-x86-*`) are compiled
     alongside `makensis.exe`. The NSIS source tree's `SCons/Tools/crossmingw.py` is loaded
     automatically on non-Windows hosts and configures `i686-w64-mingw32-windres` for
     resource compilation, embedding the icon section that `CEXEBuild` requires at startup
   - Archives the install tree with `tar` before `docker cp` to avoid macOS Docker Desktop
     silently dropping directories whose names contain spaces (`Contrib/Language files/`,
     `Contrib/Modern UI 2/`)

2. **`NSIS_SHA256` and `STRLEN_SHA256` variables removed** — no pre-built binaries are
   downloaded any more.

3. **NsProcess fix** — `NsProcess.dll` is now explicitly copied to both `x86-ansi` and
   `x86-unicode` plugin directories. Previously it was only placed in `x86-ansi`; modern NSIS
   compiles Unicode by default and resolves plugins from `x86-unicode`, so
   `nsProcess::FindProcess` would silently fail.

4. **Cleanup handler** — `trap cleanup EXIT INT TERM` removes the Docker image and container
   on exit/interrupt, preventing image accumulation during local iteration.

The plugin list (INetC, StdUtils, SpiderBanner, NsProcess, UAC, WinShell, EmbedHTML,
Nsisunz, NSISunzU, nsis7z) and their download URLs / checksums are **unchanged**.

---

### `packages/nsis/assets/nsis-test.sh`

Removes test assertions that only applied to the old pre-built bundle layout:

- **Removed:** `windows/makensisw.exe` present — the GUI-subsystem launcher is not produced
  by the source build
- **Removed:** `windows/Bin/makensis.exe` present — the old strlen_8192 zip nested the
  patched compiler under a `Bin/` subdirectory; the source build puts it directly at
  `windows/makensis.exe`
- **Removed:** `windows/Bin` directory present check
- **Removed:** `windows/makensisw.exe` present in Test 4 (NSISDIR data files)
- **Updated:** Test 3 (binary format / MZ-header check) now validates `windows/makensis.exe`
  instead of `windows/makensisw.exe`

---

### `packages/nsis/build.sh`

- `NSIS_BRANCH_OR_COMMIT` changed from the mutable tag `v312` to pinned commit SHA
  `e3f60402bcdf7be822d159b531c6e38ddf32de12` (the NSIS 3.12 release commit), ensuring
  reproducible builds even if the tag is moved
- `NSIS_SHA256` and `STRLEN_SHA256` removed (no pre-built downloads)
- Added `run_tests` function and `--target test` subcommand
- Added `--full` flag (passed through to `nsis-test.sh` for E2E install/uninstall)
- `--target all` now automatically runs the test suite after combining
- Updated help text and build-order comments

---

### `packages/nsis/assets/nsis-linux.sh` and `nsis-mac.sh`

Changed the NSIS git clone from `git clone --branch <ref>` to
`git init` + `git fetch --depth=1 origin <ref>` + `git checkout FETCH_HEAD`
so that `NSIS_BRANCH_OR_COMMIT` can be a commit SHA rather than only a branch/tag name.

---

### `packages/nsis/assets/nsis-combine.sh`

Updated the bundle README template: Windows binary description changed from
`"official pre-built binary"` to `"compiled from source via Docker + MinGW-w64"`.

---

### `.github/workflows/build-nsis.yaml`

- **Base job:** Added `docker/setup-buildx-action` step (required for the new Docker build)
- **Base job:** Added `rsync` to the `apt-get install` line (already used by the plugin
  installer but was missing from the CI dependency list)
- **Linux test matrix:** Split into two entries — `Linux (x64)` on `ubuntu-latest` and
  `Linux (arm64)` on `ubuntu-22.04-arm` — so both architectures are validated on native
  runners rather than QEMU emulation
- Minor comment updates

---

### `.changeset/tough-falcons-fry.md`

New changeset marking a **major** version bump for the `nsis` package.

---

## Cross-compilation notes

### Why stubs compile correctly with icon resources

NSIS bundles `SCons/Tools/crossmingw.py`, loaded automatically when `PLATFORM != 'win32'`.
It detects the `i686-w64-mingw32-` prefix and configures:
```python
env['RC']    = 'i686-w64-mingw32-windres'
env['RCCOM'] = '$RC $_CPPDEFFLAGS $_CPPINCFLAGS ${INCPREFIX}${SOURCE.dir} $RCFLAGS -i $SOURCE -o $TARGET'
```
The exehead `SConscript` calls `env.RES(resource.rc)` to compile the icon/bitmap resources
into an object file linked into each stub PE. This gives the stubs the `.rsrc` section that
`CEXEBuild::init()` reads to extract icon data. Without this, `makensis.exe` aborts every
compile with `Error initializing CEXEBuild: invalid icon file`.

### Workarounds required for MinGW cross-compilation

| Problem | Workaround |
|---|---|
| MinGW linker auto-appends `.exe`; SCons expects no-extension target names on Linux | `g++` wrapper creates a no-extension copy alongside the `.exe` after each link step |
| `halibut` (doc generator) cross-compiles to a Windows PE that can't execute on Linux | `gcc` wrapper intercepts the halibut link step and emits a shell-script proxy to the native binary |
| `Source/build.cpp` uses `FIELD_OFFSET` with a non-`constexpr` argument (runtime `wcslen`), rejected by MinGW-w64's strict `__builtin_offsetof` | `sed` one-liner patched in Dockerfile before `scons` |
| `makensis.exe` must not depend on `zlib1.dll` (absent on stock Windows) | `libz.dll.a` removed so the linker uses the static `libz.a` instead |
| `SCons/Config/gnu` uses `TryRun()` to detect endianness; the cross-compiled test PE cannot execute on Linux so TryRun reports failure, which NSIS interprets as big-endian and adds `-D__BIG_ENDIAN__` to `makensis_env`; `FIX_ENDIAN_INT16()` then byte-swaps ICO header fields causing `load_icon_file()` to throw `"invalid icon file"` at startup | `g++`/`gcc` wrappers append `-U__BIG_ENDIAN__` after all SCons-generated flags for compile steps, overriding the spurious `-D` |

---

## Testing

To run locally against a built bundle:
```bash
# Build (requires Docker on macOS or Linux):
cd packages/nsis && bash build.sh --target all

# Test against an existing combined bundle:
bash assets/nsis-test.sh --bundle-dir out/nsis/nsis-bundle

# E2E install/uninstall (Windows runner or Linux + Wine):
bash assets/nsis-test.sh --bundle-dir out/nsis/nsis-bundle --full
```
