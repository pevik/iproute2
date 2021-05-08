#!/bin/sh
# Copyright (c) 2017-2020 Petr Vorel <pvorel@suse.cz>
# Script for travis builds.
#
# TODO: Implement comparison of installed files. List of installed files can
# be used only for local builds as Travis currently doesn't support sharing
# file between jobs, see
# https://github.com/travis-ci/travis-ci/issues/6054

set -e

CFLAGS="${CFLAGS:--Wformat -Werror=format-security -Werror=implicit-function-declaration -Werror=return-type -fno-common}"
CC="${CC:-gcc}"

DEFAULT_PREFIX="$HOME/ltp-install"
DEFAULT_BUILD="native"
MAKE_OPTS="-j$(getconf _NPROCESSORS_ONLN)"

build_32()
{
	local dir
	local arch="$(uname -m)"

	echo "===== 32-bit $build into $PREFIX ====="

	if [ -z "$PKG_CONFIG_LIBDIR" ]; then
		if [ "$arch" != "x86_64" ]; then
			echo "ERROR: auto-detection not supported platform $arch, export PKG_CONFIG_LIBDIR!"
			exit 1
		fi

		for dir in /usr/lib/i386-linux-gnu/pkgconfig \
			/usr/lib32/pkgconfig /usr/lib/pkgconfig; do
			if [ -d "$dir" ]; then
				PKG_CONFIG_LIBDIR="$dir"
				break
			fi
		done
		if [ -z "$PKG_CONFIG_LIBDIR" ]; then
			echo "WARNING: PKG_CONFIG_LIBDIR not found, build might fail"
		fi
	fi

	CFLAGS="-m32 $CFLAGS" LDFLAGS="-m32 $LDFLAGS"
	build $1
}

build_native()
{
	echo "===== native build into $PREFIX ====="
	build $1
}

build_cross()
{
	local host=$(basename "${CC%-gcc}")
	if [ "$host" = "gcc" ]; then
		echo "Invalid CC variable for cross compilation: $CC (clang not supported)" >&2
		exit 1
	fi

	echo "===== cross-compile ${host} build into $PREFIX ====="
	build $1 "--host=$host"
}

build()
{
	local install="$1"
	shift

	run_configure ./configure --prefix=$PREFIX $@

	echo "=== build ==="
	make $MAKE_OPTS

	if [ "$install" = 1 ]; then
		echo "=== install ==="
		make $MAKE_OPTS install
	else
		echo "make install skipped, use -i to run it"
	fi
}

run_configure()
{
	local configure=$1
	shift

	export CC CFLAGS LDFLAGS PKG_CONFIG_LIBDIR
	echo "CC='$CC' CFLAGS='$CFLAGS' LDFLAGS='$LDFLAGS' PKG_CONFIG_LIBDIR='$PKG_CONFIG_LIBDIR'"

	echo "=== configure $configure $@ ==="
	if ! $configure $@; then
		echo "== ERROR: configure failed =="
		exit 1
	fi

	echo "== config.mk =="
	cat config.mk
}

usage()
{
	cat << EOF
Usage:
$0 [ -c CC ] [ -p DIR ] [ -t TYPE ]
$0 -h

Options:
-h       Print this help
-c CC    Define compiler (\$CC variable)
-p DIR   Change installation directory (--prefix), default: '$DEFAULT_PREFIX'
-t TYPE  Specify build type, default: $DEFAULT_BUILD

BUILD TYPES:
32       32-bit build (PKG_CONFIG_LIBDIR auto-detection for x86_64)
cross    cross-compile build (requires set compiler via -c switch)
native   native build
EOF
}

PREFIX="$DEFAULT_PREFIX"
build="$DEFAULT_BUILD"
install=0

while getopts "c:hio:p:t:" opt; do
	case "$opt" in
	c) CC="$OPTARG";;
	h) usage; exit 0;;
	i) install=1;;
	p) PREFIX="$OPTARG";;
	t) case "$OPTARG" in
		32|cross|native) build="$OPTARG";;
		*) echo "Wrong build type '$OPTARG'" >&2; usage; exit 1;;
		esac;;
	?) usage; exit 1;;
	esac
done

cd `dirname $0`

echo "=== compiler version ==="
$CC --version

eval build_$build $install
