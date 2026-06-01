#!/usr/bin/env node
// This file exists to prevent esbuild from using the Yarn PnP manifest in a
// parent directory. This project uses pnpm with a standard node_modules layout.
// esbuild walks up the directory tree looking for .pnp.cjs and stops at the
// first one it finds — this stub causes it to fall back to node_modules resolution.
