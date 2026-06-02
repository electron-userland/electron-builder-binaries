# Wine Portable Bundle

Builds a self-contained Wine bundle for use by electron-builder's Windows code-signing pipeline (rcedit, signtool, WiX).

## Quick Start

```bash
./build.sh                   # build + test for the current platform (~30–60 min)
./build.sh --target mac      # macOS only (no test)
./build.sh --target linux    # Linux via Docker (no test)
./build.sh --target test     # run tests against an already-built bundle
```

## Prerequisites

**macOS** — Homebrew (installed automatically if Brewfile deps are missing):

```bash
xcode-select --install       # Xcode CLI tools
```

**Linux** — Docker (the build runs inside a container):

```bash
docker info                  # verify Docker daemon is running
```

## Architecture

The bundle always targets **x86_64**, even on Apple Silicon:

- **Intel Mac** — compiled natively
- **ARM Mac** — compiled via `arch -x86_64` (Rosetta); runs under Rosetta at runtime
- **Linux** — compiled inside an `ubuntu:22.04` Docker container

x86_64 is the only architecture electron-builder's Windows toolchain requires.

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `WINE_VERSION` | `11.0` | Wine version to compile |
| `BUILD_DIR` | `./build` | Scratch build directory |
| `OUT_DIR` | `./out` | Where the `.tar.xz` artifact is written |

## Output

```
out/wine-11.0-darwin-x86_64.tar.xz
out/wine-11.0-linux-x86_64.tar.xz
```

### Bundle layout

```
wine-11.0-darwin-x86_64/
├── bin/
│   ├── wine              # Wine loader (x86_64 Mach-O / ELF)
│   ├── wine64 -> wine    # Symlink for electron-builder compatibility
│   └── wineserver        # Wine server daemon
├── lib/
│   └── wine/
│       └── x86_64-unix/  # ~30 Unix-side ELF .so files (4 MB)
│           └── ntdll.so
│           └── ...
├── share/wine/           # Data files (keyboard layouts, etc.)
└── wine-home/            # Pre-initialized Wine prefix
    ├── dosdevices/
    │   ├── c: -> ../drive_c
    │   └── z: -> /
    ├── drive_c/
    │   └── windows/
    │       └── system32/ # Core Windows DLLs (kernel32, ntdll, crypt32, …)
    └── *.reg
```

> **Note:** `lib/wine/x86_64-windows/` is **not** included. It seeds `system32/`
> during `wineboot --init` at build time, then is deleted — system32 is the DLL
> source at runtime in Wine 9+.

## Using the Bundle

electron-builder extracts the archive and points `WINEPREFIX` at the bundled `wine-home`:

```bash
tar -xJf wine-11.0-darwin-x86_64.tar.xz
export WINEPREFIX="$PWD/wine-11.0-darwin-x86_64/wine-home"
wine-11.0-darwin-x86_64/bin/wine rcedit.exe --help
```

The bundle is self-contained and does **not** require a system Wine installation.

## Build Internals

1. Downloads and verifies the Wine source tarball (SHA-256 checked)
2. Compiles with `--without-x --without-cups --without-dbus --without-freetype`
3. Runs `wineboot --init` to pre-initialize `wine-home/`
4. Removes `lib/wine/x86_64-windows/` (~770 MB) — redundant after prefix init
5. Prunes `system32/` of non-essential files (debugger, control panel, type libraries)
6. Removes `winsxs/`, `resources/`, `globalization/`, unused bin dev-tools
7. Strips binaries (`strip -x`)
8. Packages as `.tar.xz`

## Tests

The test suite (`assets/test.sh`) runs automatically after each build. It covers:

| Phase | What is tested |
|---|---|
| 1 — Assemble | Archive exists and extracts cleanly |
| 2 — Sanity | `wine --version`, binary executability, `wine-home/` structure |
| 3a — rcedit | `rcedit.exe --help` runs via Wine (win-codesign@1.2.1) |
| 3b — WiX tools | `candle.exe`, `light.exe`, `WriteZipToSetup.exe` each run with `/?` (wix-4.0.0.5512.2; skips if 7z not found) |
| 3c — signtool | `signtool.exe /?` runs via Wine (windows-kits-bundle@1.2.1) |

Run tests standalone against an existing bundle:

```bash
./build.sh --target test
# or
bash assets/test.sh --bundle-dir ./out
```

## Supported Versions

Only the versions with a known-good checksum in `build-wine.sh` are supported:

| Version | Status |
|---|---|
| 11.0 | ✅ Current |

To add a new version, update `get_checksum()` in `assets/build-wine.sh`.
