_threads="win32"
_enable_bootstrap=no
_enable_ada=yes

_basename=gcc
_base_pkg_version=4.6

#  GCC_VERSION="gcc-${_base_pkg_version}.4"
MPFR_VERSION=mpfr-2.4.2
GMP_VERSION=gmp-4.3.2
MPC_VERSION=mpc-0.8.1

# _sourcedir=${GCC_VERSION}
_sourcedir=gcc_main_development

# =========================================== #

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
    if [ ! -d  "$_sourcedir/$subfolder" ]; then
        echo "Extracting ${tarfile} to $_sourcedir/$subfolder"
        mkdir -p "$_sourcedir/$subfolder"
        tar -x --strip-components=1 -f "$tarfile" -C "$_sourcedir/$subfolder"
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

apply_edits() {
  cd ${srcdir}/${_sourcedir}

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
  local MINGW_NATIVE_PREFIX=$(cygpath -am /mingw64/x86_64-w64-mingw32)
  sed -i "s/\\/mingw\\//${MINGW_NATIVE_PREFIX//\//\\/}\\//g" gcc/config/i386/mingw32.h

  # FIX "The directory that should contain system headers does not exist: /mingw/include"
  sed -i "s|/mingw/include|/mingw32/include|g" gcc/config/i386/t-mingw-w32
  sed -i "s|/mingw/include|/mingw64/include|g" gcc/config/i386/t-mingw-w64
}

do_configure() {
  [[ -d ${srcdir}/build-x86_64-w64-mingw32 ]] && rm -rf ${srcdir}/build-x86_64-w64-mingw32
  mkdir -p ${srcdir}/build-x86_64-w64-mingw32 && cd ${srcdir}/build-x86_64-w64-mingw32

  local -a configure_opts

  local _arch=x86-64


  if [ "$_enable_bootstrap" == "yes" ]; then
    configure_opts+=("--enable-bootstrap")
  elif [ "$_enable_bootstrap" == "no" ]; then
    configure_opts+=("--disable-bootstrap")
  fi

  local _languages="c,lto"
  if [ "$_enable_fortran" == "yes" ]; then
    _languages+=",fortran"
  fi
  if [ "$_enable_ada" == "yes" ]; then
    _languages+=",ada"
  fi
  if [ "$_enable_objc" == "yes" ]; then
    _languages+=",objc,obj-c++"
  fi

  mkdir -p /opt/gcc${_base_pkg_version}_x64

  ../${_sourcedir}/configure \
    --prefix=/opt/gcc${_base_pkg_version}_x64 \
    --with-local-prefix=/mingw64/local \
    --build=i686-w64-mingw32 \
    --host=x86_64-pc-msys \
    --target=x86_64-w64-mingw32 \
    --with-native-system-header-dir=/mingw64/x86_64-w64-mingw32/include \
    --libexecdir=/opt/gcc${_base_pkg_version}_x64/lib \
    --with-arch=${_arch} \
    --with-tune=generic \
    --enable-languages=${_languages} \
    --enable-libada \
    --disable-libssp \
    --enable-shared --enable-static \
    --enable-libatomic \
    --enable-threads=${_threads} \
    --enable-graphite \
    --enable-fully-dynamic-string \
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
    --with-zlib=/usr \
    --with-pkgversion="Rev${pkgrel}, Built by stahta01 -- Tim S" \
    --with-bugurl="https://github.com/stahta01/GCC-MINGW-packages/issues" \
    --with-gnu-as --with-gnu-ld \
    "${configure_opts[@]}"
}

do_clean() {
  cd ${srcdir}/build-x86_64-w64-mingw32

  make -j1 all clean

  make -j1 install clean
}

build_and_install() {
  cd ${srcdir}/build-x86_64-w64-mingw32

  del_file_exists gcc/gtype.state || true

  make -j1 all

  make -j1 install
}

# =========================================== #

srcdir="`pwd`/src"
mkdir -p ${srcdir} && cd ${srcdir}

# Download packages
# wget -nc https://ftp.gnu.org/gnu/gcc/$GCC_VERSION/$GCC_VERSION.tar.bz2
wget -nc ftp://gcc.gnu.org/pub/gcc/infrastructure/${MPFR_VERSION}.tar.bz2
wget -nc ftp://gcc.gnu.org/pub/gcc/infrastructure/${GMP_VERSION}.tar.bz2
wget -nc ftp://gcc.gnu.org/pub/gcc/infrastructure/${MPC_VERSION}.tar.gz

# Extract packages
# extract                     ${GCC_VERSION}.tar.bz2
extract_to_gcc_folder       ${MPFR_VERSION}.tar.bz2
extract_to_gcc_folder       ${GMP_VERSION}.tar.bz2
extract_to_gcc_folder       ${MPC_VERSION}.tar.gz


# apply_edits

do_configure

# do_clean
build_and_install
