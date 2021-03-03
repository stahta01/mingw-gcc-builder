#! /usr/bin/bash
set -e
trap 'previous_command=$this_command; this_command=$BASH_COMMAND' DEBUG
trap 'echo FAILED COMMAND: $previous_command' EXIT

_local_gcc32_prefix=/c/GreenApps32/gcc_4.6.0-mingw32_x86_generic/mingw
_local_gcc64_prefix=/c/GreenApps64/gcc_4.6.0_mingw64_x86_64_K8+ada/mingw

_threads="win32"
_enable_bootstrap=no
_basename=gcc
_base_pkg_version=4.6

GCC_VERSION="gcc-${_base_pkg_version}.4"
MPFR_VERSION=mpfr-2.4.2
GMP_VERSION=gmp-4.3.2
MPC_VERSION=mpc-0.8.1

_sourcedir=${GCC_VERSION}

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

apply_patch_with_msg() {
  for _patch in "$@"
  do
    echo "Applying ${_patch}"
    patch -Nbp1 -i "${srcdir}/${_patch}"
  done
}

del_file_exists() {
  for _fname in "$@"
  do
    if [ -f ${_fname} ]; then
      rm -rf ${_fname}
    fi
  done
}

_extract_to_source_folder() {
    local tarfile="$1"
    local subfolder="$(echo "$tarfile" | sed 's/-.*$//')"
    if [ ! -d  "${_sourcedir}/$subfolder" ]; then
        echo "Extracting ${tarfile} to ${_sourcedir}/$subfolder"
        mkdir -p "${_sourcedir}/$subfolder"
        tar -x --strip-components=1 -f "$tarfile" -C "${_sourcedir}/$subfolder"
    fi
}
# =========================================== #

apply_patches_edits() {
  cd ${srcdir}/${_sourcedir}

  apply_patch_with_msg \
    104-gcc-4.6.4-Fix-texi-docs-syntax-errors.patch \
    161-gcc-4.0-cfns-fix-mismatch-in-gnu_inline-attributes.patch \
    132-gcc-4.3-dont-escape-arguments-that-dont-need-it-in-pex-win32.c.patch \
    111-gcc-4.0-fix-for-windows-not-minding-non-existant-parent-dirs.patch \
    131-gcc-4.0-windows-lrealpath-no-force-lowercase-nor-backslash.patch \
    141-gcc-4.4-ktietz-libgomp.patch \
    121-gcc-4.0-handle-use-mingw-ansi-stdio.patch || true

  # Skip installing libiberty
  sed -i 's/install_to_$(INSTALL_DEST) //' libiberty/Makefile.in

  # hack! - some configure tests for header files using "$CPP $CPPFLAGS"
  sed -i "/ac_cpp=/s/\$CPPFLAGS/\$CPPFLAGS -O2/" {libiberty,gcc}/configure

  # do not expect $prefix/mingw symlink - this should be superceded by
  # 160-mingw-dont-ignore-native-system-header-dir.patch .. but isn't!
  [[ -f configure.src ]] && {
    rm -f configure
    cp configure.src configure
  } || {
    cp configure configure.src
  }
  sed -i 's/${prefix}\/mingw\//${prefix}\//g' configure

  # change hardcoded /mingw prefix to the real prefix
  [[ -f gcc/config/i386/mingw32.h.src ]] && {
    rm -f gcc/config/i386/mingw32.h
    cp gcc/config/i386/mingw32.h.src gcc/config/i386/mingw32.h
  } || {
    cp gcc/config/i386/mingw32.h gcc/config/i386/mingw32.h.src
  }
  local MINGW_NATIVE_PREFIX=$(cygpath -am ${MINGW_PREFIX}/${MINGW_CHOST})
  sed -i "s/\\/mingw\\//${MINGW_NATIVE_PREFIX//\//\\/}\\//g" gcc/config/i386/mingw32.h

  # FIX "The directory that should contain system headers does not exist: /mingw/include"
  sed -i "s|/mingw/include|/mingw32/include|g" gcc/config/i386/t-mingw-w32
  sed -i "s|/mingw/include|/mingw64/include|g" gcc/config/i386/t-mingw-w64
}

do_configure() {
  [[ -d ${srcdir}/build-${MINGW_CHOST} ]] && rm -rf ${srcdir}/build-${MINGW_CHOST}
  mkdir -p ${srcdir}/build-${MINGW_CHOST} && cd ${srcdir}/build-${MINGW_CHOST}

  local -a configure_opts

  case "${MSYSTEM_CARCH}" in
    i686)
      configure_opts+=("--disable-sjlj-exceptions")
      configure_opts+=("--with-dwarf2")
      LDFLAGS+=" -Wl,--large-address-aware"
      export PATH="${_local_gcc32_prefix}/bin":$PATH
      export GNATBIND="${_local_gcc32_prefix}/bin/gnatbind"
      export GNATMAKE="${_local_gcc32_prefix}/bin/gnatmake"
      export CC="${_local_gcc32_prefix}/bin/gcc"
      export CXX="${_local_gcc32_prefix}/bin/g++"
      local _arch=i686
    ;;

    x86_64)
      export PATH="${_local_gcc64_prefix}/bin":$PATH
      export GNATBIND="${_local_gcc64_prefix}/bin/gnatbind"
      export GNATMAKE="${_local_gcc64_prefix}/bin/gnatmake"
      export CC="${_local_gcc64_prefix}/bin/gcc"
      export CXX="${_local_gcc64_prefix}/bin/g++"
      local _arch=x86-64
    ;;
  esac

  if [ "$_enable_bootstrap" == "yes" ]; then
    configure_opts+=("--enable-bootstrap")
  elif [ "$_enable_bootstrap" == "no" ]; then
    configure_opts+=("--disable-bootstrap")
  fi

  local _languages="c,lto,c++"
  if [ "$_enable_fortran" == "yes" ]; then
    _languages+=",fortran"
  fi
  if [ "$_enable_ada" == "yes" ]; then
    _languages+=",ada"
  fi
  if [ "$_enable_objc" == "yes" ]; then
    _languages+=",objc,obj-c++"
  fi
  
  mkdir -p ${MINGW_PREFIX}/opt/gcc

  ../${_sourcedir}/configure \
    --prefix=${MINGW_PREFIX}/opt/gcc \
    --with-local-prefix=${MINGW_PREFIX}/local \
    --build=${MINGW_CHOST} \
    --host=${MINGW_CHOST} \
    --target=${MINGW_CHOST} \
    --with-native-system-header-dir=${MINGW_PREFIX}/${MINGW_CHOST}/include \
    --libexecdir=${MINGW_PREFIX}/opt/gcc/lib \
    --with-gxx-include-dir=${MINGW_PREFIX}/include/c++/${pkgver} \
    --enable-bootstrap \
    --with-arch=${_arch} \
    --with-tune=generic \
    --enable-languages=${_languages} \
    --enable-shared --enable-static \
    --enable-libatomic \
    --enable-threads=${_threads} \
    --enable-graphite \
    --enable-fully-dynamic-string \
    --enable-libstdcxx-time=yes \
    --disable-libstdcxx-pch \
    --disable-libstdcxx-debug \
    --enable-version-specific-runtime-libs \
    --enable-lto \
    --enable-libgomp \
    --disable-multilib \
    --enable-checking=release \
    --disable-rpath \
    --disable-win32-registry \
    --disable-nls \
    --disable-werror \
    --disable-symvers \
    --with-libiconv \
    --with-zlib=${MINGW_PREFIX} \
    --with-pkgversion="Rev${pkgrel}, Built by stahta01 -- Tim S" \
    --with-bugurl="https://github.com/stahta01/GCC-MINGW-packages/issues" \
    --with-gnu-as --with-gnu-ld \
    "${configure_opts[@]}"
}

do_clean() {
  cd ${srcdir}/build-${MINGW_CHOST}

  make -j1 all clean

  make -j1 install clean
}

build_and_install() {
  cd ${srcdir}/build-${MINGW_CHOST}

  del_file_exists gcc/gtype.state || true

  make -j1 all

  make -j1 install
}

srcdir="`pwd`/src"
mkdir -p ${srcdir} && cd ${srcdir}

# Download packages
wget -nc https://ftp.gnu.org/gnu/gcc/$GCC_VERSION/$GCC_VERSION.tar.bz2
wget -nc ftp://gcc.gnu.org/pub/gcc/infrastructure/${MPFR_VERSION}.tar.bz2
wget -nc ftp://gcc.gnu.org/pub/gcc/infrastructure/${GMP_VERSION}.tar.bz2
wget -nc ftp://gcc.gnu.org/pub/gcc/infrastructure/${MPC_VERSION}.tar.gz

# Extract packages
extract                     ${GCC_VERSION}.tar.bz2
extract_to_gcc_folder       ${MPFR_VERSION}.tar.bz2
extract_to_gcc_folder       ${GMP_VERSION}.tar.bz2
extract_to_gcc_folder       ${MPC_VERSION}.tar.gz

# Patch GCC and support libs
# apply_patches_edits

# 
# do_configure

# Build GCC and support libs
# do_clean
build_and_install