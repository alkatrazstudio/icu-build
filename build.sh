#!/usr/bin/env bash
set -ex

cd "$(dirname -- "${BASH_SOURCE[0]}")"
ROOT_DIR="$(pwd)"

. ./vars

# download the whole source tree because icu4c release archives ignore build flags
ICU_DOWNLOAD_URL="https://github.com/unicode-org/icu/archive/refs/tags/release-$ICU_MAJOR_VER-$ICU_MINOR_VER.tar.gz"

# https://github.com/unicode-org/icu/blob/main/icu4c/source/runConfigureICU
case "$OSTYPE" in
    darwin*)
        ICU_TARGET=MacOSX
        ARCHIVE_SUFFIX=osx
        ;;

    msys)
        # when on MSYS2, pose as Linux
        # also, clang build does not work on MSYS2
        ICU_TARGET=Linux/gcc
        ARCHIVE_SUFFIX=msys
        ;;

    *)
        ICU_TARGET=Linux/gcc
        ARCHIVE_SUFFIX=linux
        ;;
esac

if [[ -z $ICU_NO_DOWNLOAD ]]
then
    rm -rf src icu-release-*
    curl -SsL "$ICU_DOWNLOAD_URL" | tar -xzf-
    mv icu-release-* src
fi
SRC_DIR="$ROOT_DIR/src"

BUILD_DIR="$ROOT_DIR/build"
rm -rf "$BUILD_DIR"
mkdir "$BUILD_DIR"

DIST_DIR="$ROOT_DIR/icu"
rm -rf "$DIST_DIR"
mkdir "$DIST_DIR"

cd "$BUILD_DIR"

# https://unicode-org.github.io/icu/userguide/icu4c/packaging.html#disable-icu-features
# https://github.com/unicode-org/icu/blob/main/icu4c/source/common/unicode/uconfig.h
# https://unicode-org.github.io/icu/userguide/icu_data/buildtool.html#file-slicing-coarse-grained-features
# https://unicode-org.github.io/icu/userguide/icu_data/buildtool.html#additive-and-subtractive-modes
env CPPFLAGS="\
        -DUCONFIG_NO_BREAK_ITERATION=1 \
        -DUCONFIG_NO_IDNA=1 \
        -DUCONFIG_NO_FORMATTING=1 \
        -DUCONFIG_NO_TRANSLITERATION=1 \
        -DUCONFIG_NO_REGULAR_EXPRESSIONS=1 \
        -DUCONFIG_NO_COLLATION=1 \
        -DUCONFIG_ONLY_HTML_CONVERSION=1 \
    " \
    ICU_DATA_FILTER_FILE="$ROOT_DIR/filters.json" \
    "$SRC_DIR/icu4c/source/runConfigureICU" \
    "$ICU_TARGET" \
    --prefix="$DIST_DIR"
    make
    make install

# stip binaries since it's not done automatically
cd "$DIST_DIR"
case "$OSTYPE" in
    darwin*)
        find lib -type f -iname '*.dylib' -exec strip {} \;
        ;;

    msys)
        find bin -type f -iname '*.dll' -exec strip {} \;
        ;;

    *)
        find lib -type f -iname '*.so.*.*' -exec strip {} \;
        ;;
esac

# make pkg-config files not dependant on the files location
find lib/pkgconfig/ -type f -name '*.pc' -exec sed -i.bak 's~^prefix =.*~prefix = ${pcfiledir}/../..~' {} \;
rm -f lib/pkgconfig/*.bak

cd "$ROOT_DIR"
tar -cf- icu | xz -c9e - > "icu-$ARCHIVE_SUFFIX.tar.xz"

echo "DONE!"
