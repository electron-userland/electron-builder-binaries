#!/usr/bin/env bash
set -ex

BASEDIR=$(cd "$(dirname "$0")/.." && pwd)
cd $BASEDIR
OUTPUT_DIR=$BASEDIR/${OUTPUT_SUBDIR:-fpm}
rm -rf $OUTPUT_DIR
mkdir -p $OUTPUT_DIR

TMP_DIR=/tmp/fpm
rm -rf $TMP_DIR
mkdir -p $TMP_DIR

RUBY_VERSION=3.1.0
FPM_VERSION=${FPM_VERSION:-1.16.0}
echo "FPM version: $FPM_VERSION"

# rm -f $BASEDIR/Gemfile

# gem install bundler --no-document --quiet
# bundle init

# echo "\"ruby\" \"$RUBY_VERSION\"" >> $BASEDIR/Gemfile
# echo "gem \"fpm\", \"$FPM_VERSION\"" >> $BASEDIR/Gemfile

# bundle install --without=development --path=$TMP_DIR/

gem install fpm --version $FPM_VERSION --install-dir $TMP_DIR --no-document --quiet

cp -a $TMP_DIR/* $OUTPUT_DIR
echo $FPM_VERSION > $OUTPUT_DIR/VERSION

# create symlink to fpm relative to the output directory so that it correctly copies out of the docker image
cd $OUTPUT_DIR
ln -s ./ruby/$RUBY_VERSION/bin/fpm fpm
