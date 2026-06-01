# Wine Portable Bundle Builder

Compile Wine from source to create portable, self-contained bundles.

**Simple approach:** Builds for current architecture only, uses Rosetta when needed.

## Quick Start

```bash
./build.sh
```

Builds Wine for your current architecture (30-60 minutes).

## Prerequisites

```bash
# Install Xcode Command Line Tools
xcode-select --install
```

**That's it.** No Homebrew, no dependencies, nothing.

Builds Wine **without FreeType** (fonts work via macOS fallback).

## Architecture Strategy

**Always builds x86_64 Wine** (works on both Intel and ARM):
- **Intel Mac** → Builds x86_64 natively
- **ARM Mac** → Builds x86_64 via Rosetta (uses x86_64 Homebrew at `/usr/local`)

**Why x86_64 on ARM?**
- ✅ Much simpler (no PE cross-compilation tools needed)
- ✅ Works perfectly via Rosetta
- ✅ Same binary works on both Intel and ARM Macs
- ✅ Avoids ARM64 Wine complications

**Native ARM64 Wine is not worth it:**
- ❌ Requires llvm-mingw cross-compilation setup
- ❌ Much more complex to build
- ❌ Limited benefit (Rosetta works great)

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `WINE_VERSION` | Wine version to build | `11.0` |
| `BUILD_DIR` | Build output directory | `./build` |

## Examples

```bash
# Build Wine 11.0 (default)
./build.sh

# Build Wine 9.0
WINE_VERSION=9.0 ./build.sh

# Build for Linux (requires Docker)
OS_TARGET=linux ./build.sh
```

## GitHub Actions Usage

Perfect for CI/CD with separate runners:

```yaml
jobs:
  build-intel:
    runs-on: macos-15-intel  # Intel runner
    steps:
      - run: ./build.sh
      # Produces: wine-11.0-darwin-x86_64.tar.gz
  
  build-arm:
    runs-on: macos-15  # ARM runner
    steps:
      - run: ./build.sh
      # Produces: wine-11.0-darwin-x86_64.tar.gz (via Rosetta)
```

Both produce x86_64 binaries that work everywhere!

## What You Get

A **portable Wine bundle**:
- Latest Wine version (not stuck on 4.0.3!)
- Pre-initialized Wine prefix
- Cleaned up (~60% smaller)
- Self-contained, no dependencies
- Works on both Intel and ARM Macs

## Output Structure

```
wine-11.0-darwin-x86_64/
├── bin/wine64              # Wine binary
├── lib/                    # Libraries
├── share/wine/             # Data files
├── wine-home/              # Pre-initialized prefix
│   ├── dosdevices/
│   │   ├── c: -> ../drive_c
│   │   └── z: -> /
│   ├── drive_c/
│   └── *.reg
├── wine-launcher.sh        # Launcher
└── README.md
```

## Using the Bundle

```bash
tar -xzf wine-11.0-darwin-x86_64.tar.gz
cd wine-11.0-darwin-x86_64
./wine-launcher.sh notepad
```

## Build Time

- **30-60 minutes** depending on your machine
- First build downloads dependencies (~5-10 min extra)
- Subsequent builds reuse cached dependencies

## Cleanup

```bash
# Remove build artifacts but keep dependencies (for faster rebuilds)
rm -rf build/wine-* build/downloads

# Remove everything
rm -rf build/
```

## Available Wine Versions

- **11.0** (latest stable, recommended)
- **9.0**
- **8.0**

Source: https://dl.winehq.org/wine/source/

## Why Not Use Homebrew?

Homebrew installs to system directories with external dependencies. Not portable!

This creates **self-contained bundles** you can distribute.

## License

Wine is free software released under the GNU LGPL.