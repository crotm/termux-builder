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
ls $NDK
LLVM_PATH="${NDK}/toolchains/llvm/prebuilt/linux-x86_64"
ls $LLVM_PATH
if [ ! -d "$LLVM_PATH/bin" ]; then
	echo "ERROR: no NDK toolchain at $LLVM_PATH - run setup-android-sdk.sh first" >&2
	exit 1
fi

echo "--- Starting Clang Setup (Android 17 / Cinnamon Bun Era) ---"
echo "NDK path: $NDK"
echo "Clang version: $CLANG_VERSION (branch: $CLANG_BRANCH)"

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

# 3. Regenerate the NDK-style API wrapper scripts (API 21-36). Unlike NDK
# clang, the AOSP prebuilt has no default sysroot baked in, so the wrappers
# pass the NDK sysroot explicitly (a --sysroot given later on the command
# line still takes precedence).
echo "Generating API wrappers..."
cd "${LLVM_PATH}/bin"
for arch in aarch64-linux-android armv7a-linux-androideabi i686-linux-android x86_64-linux-android; do
	for api in $(seq 21 36); do
		for suffix in clang clang++; do
			printf '#!/usr/bin/env bash\nbin_dir=$(dirname "$0")\nif [ "$1" != "-cc1" ]; then\n    "$bin_dir/%s" --target=%s%s --sysroot "$bin_dir/../sysroot" "$@"\nelse\n    # Target is already an argument.\n    "$bin_dir/%s" "$@"\nfi\n' \
				"${suffix}" "${arch}" "${api}" "${suffix}" \
				> "${arch}${api}-${suffix}"
			chmod +x "${arch}${api}-${suffix}"
		done
	done
done

echo "--- Clang Setup Complete ---"
