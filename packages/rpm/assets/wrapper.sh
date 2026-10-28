#!/bin/sh
# Relocatable entrypoint for the bundled rpm tools. Ignores host rpm configuration
# (/etc/rpm/*, /usr/lib/rpm/*, ~/.rpmmacros, ~/.rpmrc, ~/.config/rpm) so output is
# identical on every build host, then applies electron-builder's pinned macros.
here=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
RPM_CONFIGDIR="$here/lib/rpm"
MAGIC="$here/share/misc/magic.mgc"
export RPM_CONFIGDIR MAGIC
c="$RPM_CONFIGDIR"
exec "$here/libexec/$(basename -- "$0")" \
    --rcfile "$c/rpmrc" \
    --macros "$c/macros:$c/macros.d/macros.*:$c/platform/%{_target}/macros:$c/fileattrs/*.attr:$c/electron-builder/macros" \
    "$@"
