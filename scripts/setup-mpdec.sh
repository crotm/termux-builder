#!/bin/bash
# setup-mpdec.sh - cross-compile libmpdec (mpdecimal) with the NDK
# toolchain and install it into the NDK sysroot so packages can link it.

set -e -u

# Used by termux_download for its temporary download file (same
# default as setup-android-sdk.sh):
: "${TERMUX_PKG_TMPDIR:="/tmp"}"

# Sets $NDK, the path setup-android-sdk.sh installed the NDK to
# (respects an already-exported $NDK):
. "$(cd "$(dirname "$0")"; pwd)/properties.sh"
. "$(cd "$(dirname "$0")"; pwd)/build/termux_download.sh"

MPDEC_VERSION=4.0.1
MPDEC_SHA256=96d33abb4bb0070c7be0fed4246cd38416188325f820468214471938545b1ac8
MPDEC_URL="https://www.bytereef.org/software/mpdecimal/releases/mpdecimal-${MPDEC_VERSION}.tar.gz"

# The Android arch/API the library is built for. Keep the API level in
# sync with TERMUX_PKG_API_LEVEL (24) used elsewhere in the build.
MPDEC_HOST=aarch64-linux-android
MPDEC_API=24

LLVM_PATH="${NDK}/toolchains/llvm/prebuilt/linux-x86_64"
LLVM_BIN="${LLVM_PATH}/bin"

if [ ! -x "${LLVM_BIN}/${MPDEC_HOST}${MPDEC_API}-clang" ]; then
	echo "ERROR: no NDK clang wrapper at ${LLVM_BIN}/${MPDEC_HOST}${MPDEC_API}-clang - run setup-clang.sh first" >&2
	exit 1
fi

echo "--- Building libmpdec ${MPDEC_VERSION} for ${MPDEC_HOST}${MPDEC_API} ---"

BUILD_TMP=$(mktemp -d)
trap 'rm -rf "$BUILD_TMP"' EXIT

termux_download "$MPDEC_URL" "$BUILD_TMP/mpdecimal.tar.gz" "$MPDEC_SHA256"
tar -xzf "$BUILD_TMP/mpdecimal.tar.gz" -C "$BUILD_TMP"
cd "$BUILD_TMP/mpdecimal-${MPDEC_VERSION}"

export CC="${LLVM_BIN}/${MPDEC_HOST}${MPDEC_API}-clang"
export CXX="${LLVM_BIN}/${MPDEC_HOST}${MPDEC_API}-clang++"
export AR="${LLVM_BIN}/llvm-ar"
export RANLIB="${LLVM_BIN}/llvm-ranlib"
export STRIP="${LLVM_BIN}/llvm-strip"

# --host makes configure treat this as a cross build (no target-binary
# execution); install into the NDK sysroot so the headers and libs are on
# the default search path of the wrapper toolchain.
./configure \
	--host="${MPDEC_HOST}" \
	--prefix="${LLVM_PATH}/sysroot/usr"

make -j"$(nproc)"
make install

echo "-----------------"
ls -l "${LLVM_PATH}/sysroot/usr/lib/libmpdec"* || true
ls -l "${LLVM_PATH}/sysroot/usr/include/mpdecimal.h" || true

# Smoke test: the freshly installed headers/libs must compile and link
# against the NDK toolchain for the target arch.
echo "Smoke testing libmpdec..."
cat > "$BUILD_TMP/mpdec-test.c" <<'EOF'
#include <mpdecimal.h>
int main(void) {
	mpd_context_t ctx;
	mpd_defaultcontext(&ctx);
	return 0;
}
EOF
"$CC" "$BUILD_TMP/mpdec-test.c" -lmpdec -o "$BUILD_TMP/mpdec-test"

echo "--- libmpdec Setup Complete ---"
