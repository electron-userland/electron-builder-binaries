#!/usr/bin/env bash
set -e

BASEDIR=$(cd "$(dirname "$0")/.." && pwd)
cd $BASEDIR
OUTPUT_DIR=$BASEDIR/out/linux-tools
rm -rf $OUTPUT_DIR
mkdir -p $OUTPUT_DIR

TMP_DIR=/tmp/linux-tools
rm -rf $TMP_DIR
mkdir -p $TMP_DIR/Cellar $TMP_DIR/bin $TMP_DIR/opt

brew install gettext glib gnu-tar libffi libgsf libtool lzip makedepend openssl@3 osslsigncode pcre
BREW_LOCATION=$(brew --prefix)

declare -a CELLAR_PACKAGES=(
    gettext
    glib
    gnu-tar
    libffi
    libgsf
    libtool
    lzip
    makedepend
    openssl@3
    osslsigncode
    pcre
)

declare -a BIN_PACKAGES=(
    brew
    # gapplication
    gdbus
    gdbus-codegen
    gio
    gio-querymodules
    glib-compile-resources
    glib-compile-schemas
    glib-genmarshal
    glib-gettextize
    glib-mkenums
    glibtool
    glibtoolize
    gobject-query
    gresource
    gsettings
    gsf
    gsf-office-thumbnailer
    gsf-vba-dump
    gtar
    gtester
    gtester-report
    lzip
    makedepend
    osslsigncode
    pcre-config
    pcregrep
    pcretest
)

declare -a OPT_PACKAGES=(
    gettext
    glib
    gnu-tar
    libffi
    libgsf
    libtool
    lzip
    makedepend
    openssl
    openssl@3.5
    osslsigncode
    pcre
    pcre1
)

# ls -R $BREW_LOCATION

# copy relevant files for linux-tools to function. DO NOT COPY THE ENTIRE CELLAR
# because it will be too large and will contain files that are not needed.
for package in "${CELLAR_PACKAGES[@]}"; do
    cp -a $BREW_LOCATION/Cellar/$package $TMP_DIR/Cellar/
    echo "Copied $package to $TMP_DIR/Cellar/"
done
for package in "${BIN_PACKAGES[@]}"; do
    cp -a $BREW_LOCATION/bin/$package $TMP_DIR/bin/
    echo "Copied $package to $TMP_DIR/bin/"
done
for package in "${OPT_PACKAGES[@]}"; do
    cp -a $BREW_LOCATION/opt/$package $TMP_DIR/opt/
    echo "Copied $package to $TMP_DIR/opt/"
done

cp -a $TMP_DIR/* $OUTPUT_DIR
rm -rf $TMP_DIR
