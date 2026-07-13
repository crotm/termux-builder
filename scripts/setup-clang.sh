#!/bin/bash
# setup-clang.sh - replace the clang in the NDK toolchain with a newer
# prebuilt from AOSP.

set -e -u

CLANG_VERSION=clang-r596125
# clang-r596125 only exists on the main-kernel branch of the AOSP
# prebuilts repo, not on main:
# https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/refs/heads/main-kernel/
CLANG_BRANCH=main-kernel

# Sets $NDK, the path setup-android-sdk.sh installed the NDK to
# (respects an already-exported $NDK):
. "$(cd "$(dirname "$0")"; pwd)/properties.sh"
LLVM_PATH="${NDK}/toolchains/llvm/prebuilt/linux-x86_64"

if [ ! -d "$LLVM_PATH/bin" ]; then
	echo "ERROR: no NDK toolchain at $LLVM_PATH - run setup-android-sdk.sh first" >&2
	exit 1
fi
ls "$LLVM_PATH"
echo "----------------"
ls "$LLVM_PATH/bin"
echo "----------------"
cat "$LLVM_PATH/AndroidVersion.txt"

echo "--- Starting Clang Setup (Android 17 / Cinnamon Bun Era) ---"
echo "NDK path: $NDK"
echo "Clang version: $CLANG_VERSION (branch: $CLANG_BRANCH)"

# The API levels the wrappers can target are exactly the ones the NDK
# sysroot ships per-API libraries for (e.g. 21..35 in NDK r29) - derive
# them instead of hardcoding:
API_LEVELS=$(ls "$LLVM_PATH/sysroot/usr/lib/aarch64-linux-android" | grep -E '^[0-9]+$' | sort -n)
if [ -z "$API_LEVELS" ]; then
	echo "ERROR: no per-API library dirs found in the NDK sysroot" >&2
	exit 1
fi
MIN_API=$(echo "$API_LEVELS" | head -1)
echo "Sysroot API levels: $(echo $API_LEVELS)"

# Remember the NDK's clang major version (e.g. 21) - the new prebuilt has
# a different one (e.g. 22), and some tooling resolves lib/clang/<major>:
NDK_CLANG_MAJOR=$(basename "$(ls -d "$LLVM_PATH"/lib/clang/* | head -1)")

# 1. Fetch the AOSP clang prebuilt (single branch, blobs only for the
# sparse-checked-out directory)
echo "Fetching $CLANG_VERSION from AOSP..."
CLANG_TMP=$(mktemp -d)
git clone --depth 1 --branch "$CLANG_BRANCH" --filter=blob:none --sparse \
	https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 \
	"$CLANG_TMP"
git -C "$CLANG_TMP" sparse-checkout set "$CLANG_VERSION"
if [ ! -x "$CLANG_TMP/$CLANG_VERSION/bin/clang" ]; then
	echo "ERROR: $CLANG_VERSION not found on branch $CLANG_BRANCH" >&2
	exit 1
fi

# 2. Replace the NDK clang with it, keeping the NDK sysroot
echo "Installing clang into the NDK toolchain..."
find "$LLVM_PATH" -mindepth 1 -maxdepth 1 ! -name sysroot -exec rm -rf {} +
mv "$CLANG_TMP/$CLANG_VERSION"/* "$LLVM_PATH/"
rm -rf "$CLANG_TMP"
echo "-----------------"
ls "$LLVM_PATH"
echo "----------------"
cat "$LLVM_PATH/AndroidVersion.txt"

# Compatibility symlink for tooling that looks up the resource dir by the
# NDK's clang major version (e.g. lib/clang/21 -> 22):
NEW_CLANG_MAJOR=$(basename "$(ls -d "$LLVM_PATH"/lib/clang/* | head -1)")
if [ "$NDK_CLANG_MAJOR" != "$NEW_CLANG_MAJOR" ]; then
	ln -sfn "$NEW_CLANG_MAJOR" "$LLVM_PATH/lib/clang/$NDK_CLANG_MAJOR"
	echo "Symlinked lib/clang/$NDK_CLANG_MAJOR -> $NEW_CLANG_MAJOR"
fi

# 3. Regenerate the NDK-style API wrapper scripts for the API levels the
# sysroot supports. Unlike NDK clang, the AOSP prebuilt has no default
# sysroot baked in, so the wrappers pass the NDK sysroot explicitly (a
# --sysroot given later on the command line still takes precedence).
echo "Generating API wrappers..."
cd "${LLVM_PATH}/bin"
for arch in aarch64-linux-android armv7a-linux-androideabi i686-linux-android x86_64-linux-android; do
	for api in $API_LEVELS; do
		for suffix in clang clang++; do
			printf '#!/usr/bin/env bash\nbin_dir=$(dirname "$0")\nif [ "$1" != "-cc1" ]; then\n    "$bin_dir/%s" --target=%s%s --sysroot "$bin_dir/../sysroot" "$@"\nelse\n    # Target is already an argument.\n    "$bin_dir/%s" "$@"\nfi\n' \
				"${suffix}" "${arch}" "${api}" "${suffix}" \
				> "${arch}${api}-${suffix}"
			chmod +x "${arch}${api}-${suffix}"
		done
	done
done

# 4. Smoke test: the toolchain must be able to build and link a real
# Android binary (catches missing builtins, sysroot or wrapper problems):
echo "Smoke testing the toolchain..."
SMOKE_DIR=$(mktemp -d)
echo 'int main(void){return 0;}' > "$SMOKE_DIR/test.c"
"$LLVM_PATH/bin/aarch64-linux-android${MIN_API}-clang" "$SMOKE_DIR/test.c" -o "$SMOKE_DIR/test"
echo 'int main(){return 0;}' > "$SMOKE_DIR/test.cpp"
"$LLVM_PATH/bin/aarch64-linux-android${MIN_API}-clang++" -c "$SMOKE_DIR/test.cpp" -o "$SMOKE_DIR/test.o"
rm -rf "$SMOKE_DIR"
"$LLVM_PATH/bin/clang" --version

echo "--- Clang Setup Complete ---"
