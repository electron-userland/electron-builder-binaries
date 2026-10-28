# Sources of the binaries in this bundle

The binaries in this bundle were built from, or copied unmodified out of, the exact sources listed below,
per platform. `LICENSES/MANIFEST.tsv` maps every binary to its components, and `LICENSES/<component>/` holds
each component's license text, taken from that component's own source tree, from the Ubuntu 18.04 build
image (`/usr/share/doc/<package>/copyright` and the `/usr/share/common-licenses/` texts it refers to) or from
the Homebrew keg the library was copied from.

The complete corresponding source code of every component under the GNU GPL or LGPL is available at the
locations below: upstream tags and commits, Ubuntu source packages (`apt-get source <package>=<version>` on
Ubuntu 18.04, or Launchpad) and Homebrew formula source tarballs. Components that were modified for this
build say so and list the exact changes (see also `LICENSES/<component>/MODIFICATIONS`).

The build scripts are in https://github.com/electron-userland/electron-builder-binaries/tree/master/packages/appimage.
