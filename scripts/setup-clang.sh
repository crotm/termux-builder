#!/bin/bash
# setup-clang.sh

set -e -u

# Define the version internally as requested
export CLANG_VERSION=clang-r596125

# Ensure NDK path is known
: "${ANDROID_HOME:?NDK environment variable must be set. Please run this from the main build script or export NDK path.}"

echo "--- Starting Clang Setup (Android 17 / Cinnamon Bun Era) ---"
echo "NDK Path: $ANDROID_HOME"
echo "Clang Version: $CLANG_VERSION"

LLVM_PATH="${ANDROID_HOME}/toolchains/llvm/prebuilt/linux-x86_64"

# 1. Clear existing LLVM prebuilts (except sysroot)
# This removes the default Clang that came with the NDK zip
echo "Cleaning existing NDK toolchain..."
find "$LLVM_PATH" -mindepth 1 -maxdepth 1 ! -name sysroot -exec rm -rf {} +

# 2. Clone the specific AOSP Clang version
echo "Fetching Clang $CLANG_VERSION from AOSP..."
CLANG_TMP="/tmp/clang-repo-$(date +%s)"
git clone --depth 1 --filter=blob:none --sparse https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 "$CLANG_TMP"
cd "$CLANG_TMP"
git sparse-checkout set "$CLANG_VERSION"

# 3. Move the new Clang into the NDK
echo "Installing Clang to NDK..."
mv "$CLANG_VERSION"/* "$LLVM_PATH/"
cd /
rm -rf "$CLANG_TMP"

# 4. Generate API wrappers (Official range: 21 to 35)
echo "Generating API wrappers..."
cd "${LLVM_PATH}/bin"
for arch in aarch64-linux-android armv7a-linux-androideabi i686-linux-android x86_64-linux-android; do
    for api in $(seq 21 35); do
        for suffix in clang clang++; do
            printf '#!/usr/bin/env bash\nbin_dir=$(dirname "$0")\nif [ "$1" != "-cc1" ]; then\n    "$bin_dir/%s" --target=%s%s "$@"\nelse\n    # Target is already an argument.\n    "$bin_dir/%s" "$@"\nfi\n' \
                "${suffix}" "${arch}" "${api}" "${suffix}" \
                > "${arch}${api}-${suffix}"
            chmod +x "${arch}${api}-${suffix}"
        done
    done
done

echo "--- Clang Setup Complete ---"
