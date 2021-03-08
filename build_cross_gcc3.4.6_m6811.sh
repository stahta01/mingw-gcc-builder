#! /bin/bash
set -e
trap 'previous_command=$this_command; this_command=$BASH_COMMAND' DEBUG
trap 'echo FAILED COMMAND: $previous_command' EXIT

#--------------------------------------------------------------------------------------------------
# This script will download packages for, configure, build and install a GCC m6811 cross-compiler.
# Customize the variables (INSTALL_PATH, HOST, PARALLEL_MAKE, etc.) to your liking before running.
#
# Manually forked from https://gist.github.com/preshing/41d5c7248dea16238b60
#
#--------------------------------------------------------------------------------------------------

INSTALL_PATH=/opt/local/cross
HOST=x86_64-pc-msys
PARALLEL_MAKE=-j1
BUILD_PREFIX=build-m6811
CONFIGURATION_OPTIONS="--disable-multilib --disable-threads" # --disable-shared
TARGET=m6811-elf
BINUTILS_VERSION=binutils-2.18
NEWLIB_VERSION=newlib-1.15.0
GCC_VERSION=gcc-3.4.6
MPFR_VERSION=mpfr-2.4.2
GMP_VERSION=gmp-4.3.2

BUILD_BIN_UTILS=1
BUILD_GCC_1=1
BUILD_GCC_3=1
BUILD_NEWLIB=1

apply_patch_with_msg() {
    for _fname in "$@"
    do
        if patch --dry-run -Nbp1 -i "${_fname}" ; then
            echo "Applying ${_fname}"
            patch -Nbp1 -i "${_fname}"
        else
            echo "Skipping ${_fname}"
        fi
    done
}

extract() {
    local tarfile="$1"
    local extracted="$(echo "$tarfile" | sed 's/\.tar.*$//')"
    if [ ! -d  "$extracted" ]; then
        echo "Extracting ${tarfile}"
        tar -xf $tarfile
    fi
}

extract_to_gcc_folder() {
    local tarfile="$1"
    local subfolder="$(echo "$tarfile" | sed 's/-.*$//')"
    if [ ! -d  "$GCC_VERSION/$subfolder" ]; then
        echo "Extracting ${tarfile} to $GCC_VERSION/$subfolder"
        mkdir -p "$GCC_VERSION/$subfolder"
        tar -x --strip-components=1 -f "$tarfile" -C "$GCC_VERSION/$subfolder"
    fi
}

update_configs() {
    local targetfolder="$1"

    cp config.guess $targetfolder/config.guess
    cp config.sub $targetfolder/config.sub
}

# Download packages
# export http_proxy=$HTTP_PROXY https_proxy=$HTTP_PROXY ftp_proxy=$HTTP_PROXY
wget -nc ftp://ftp.gnu.org/gnu/binutils/$BINUTILS_VERSION.tar.bz2
wget -nc ftp://ftp.gnu.org/gnu/gcc/$GCC_VERSION/$GCC_VERSION.tar.gz
wget -nc ftp://sourceware.org/pub/newlib/$NEWLIB_VERSION.tar.gz
wget -nc ftp://gcc.gnu.org/pub/gcc/infrastructure/$MPFR_VERSION.tar.bz2
wget -nc ftp://gcc.gnu.org/pub/gcc/infrastructure/$GMP_VERSION.tar.bz2
wget -nc https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.sub
wget -nc https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.guess

# Extract packages
extract                 $BINUTILS_VERSION.tar.bz2
extract                 $GCC_VERSION.tar.gz
extract_to_gcc_folder   $MPFR_VERSION.tar.bz2
extract_to_gcc_folder   $GMP_VERSION.tar.bz2
extract                 $NEWLIB_VERSION.tar.gz

# Patch packages
update_configs $BINUTILS_VERSION
update_configs $GCC_VERSION
update_configs $GCC_VERSION/mpfr
update_configs $GCC_VERSION/gmp
update_configs $NEWLIB_VERSION

# These patches are from https://packages.debian.org/sid/binutils-m68hc1x
cd $BINUTILS_VERSION && apply_patch_with_msg \
  ../001-bnu-2.18-m68hc11.patch \
  ../002-bnu-2.18-missing_makeinfo.patch \
  ../003-bnu-2.18-fix-format-security.patch \
  ../004-bnu-2.18-fix_texinfo_warning.patch
cd .. ;

# Patch 704 is combined fixes from later GCC versions
cd $GCC_VERSION && apply_patch_with_msg \
    ../704-gcc-3.4-Fix-texi-docs-syntax-errors.patch
cd .. ;

if [ $BUILD_BIN_UTILS -ne 0 ]; then
    # Step 1. Binutils
    mkdir -p $BUILD_PREFIX-binutils
    cd $BUILD_PREFIX-binutils
    ../$BINUTILS_VERSION/configure --prefix=$INSTALL_PATH --host=$HOST --target=$TARGET --disable-werror $CONFIGURATION_OPTIONS
    make $PARALLEL_MAKE
    make install
    cd ..
fi

export PATH=$INSTALL_PATH/bin:$PATH

if [ $BUILD_GCC_1 -ne 0 ]; then
    # Step 3. C/C++ Compilers
    mkdir -p $BUILD_PREFIX-gcc
    cd $BUILD_PREFIX-gcc
    ../$GCC_VERSION/configure --enable-obsolete  --with-newlib --prefix=$INSTALL_PATH --host=$HOST --target=$TARGET --enable-languages=c,c++ $CONFIGURATION_OPTIONS
    make $PARALLEL_MAKE all-gcc
    make install-gcc
    cd ..
fi

if [ $BUILD_NEWLIB -ne 0 ]; then
    # Steps 4-6: Newlib
    mkdir -p $BUILD_PREFIX-newlib
    cd $BUILD_PREFIX-newlib
    ../$NEWLIB_VERSION/configure --prefix=$INSTALL_PATH --host=$HOST --target=$TARGET $CONFIGURATION_OPTIONS
    make $PARALLEL_MAKE
    make install
    cd ..
fi

if [ $BUILD_GCC_3 -ne 0 ]; then
    # Step 7. Standard C++ Library & the rest of GCC
    cd $BUILD_PREFIX-gcc
    make $PARALLEL_MAKE all
    make install
    cd ..
fi

trap - EXIT
echo 'Success!'
