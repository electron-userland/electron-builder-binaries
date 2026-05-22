# electron-builder-binaries

This repo provides the required toolsets that [electron-builder](http://github.com/electron-userland/electron-builder) downloads on demand (e.g. to code sign windows application, to make AppX, assemble DMGs, bundle AppImage, etc).

The toolset (in Releases) have their version and checksum hardcoded in electron-builder's code. This ensures that even if this repository or your network gets compromised, electron-builder tooling will not be affected.

The goals of this repo are:
- To provide a secure closed-loop tooling ecosystem that electron-builder can rely on.
- Serve toolsets on-demand to reduce (or remove entirely) the load/overhead of a pre-configuring a dev environment.

## Licensing

### Artifacts

All toolsets collected/stored/distributed from this repo retain their original licensing; their LICENSE or COPYING file(s) are downloaded and included within each toolset bundle within `artifacts` dir.

### Repo License
This applies to configurations/scripts that compile and/or bundle toolsets.

Copyright 2026 electron-userland

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.