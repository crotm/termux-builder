# Build with:
#	docker build -t ghcr.io/crotm/termux-builder .
# Push to GitHub registry with:
#	docker push ghcr.io/crotm/termux-builder
# This is done after changing this file or any of the
# scripts/setup-{ubuntu,android-sdk,clang,cgct}.sh setup scripts.
FROM ubuntu:26.04

# Fix locale to avoid warnings:
ENV LANG=en_US.UTF-8

# Needed for setup:
RUN rm -rf /tmp/termux-packages
RUN mkdir -p /tmp/termux-packages
RUN mkdir -p /tmp/termux-packages/scripts
COPY ./llvm-snapshot.gpg.key ./properties.sh ./setup-android-sdk.sh ./setup-cgct.sh ./setup-clang.sh ./setup-mpdec.sh ./setup-ubuntu.sh /tmp/termux-packages/scripts/
RUN mkdir -p /tmp/termux-packages/scripts/build
COPY ./build/termux_download.sh /tmp/termux-packages/scripts/build/

# Setup needed packages and the Android SDK and NDK and the CGCT:
RUN apt-get update && \
	apt-get -yq upgrade && \
	apt-get install -yq sudo lsb-release software-properties-common && \
	userdel ubuntu && \
	useradd -u 1001 -U -m -s /bin/bash builder && \
	echo "builder ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/builder && \
	chmod 0440 /etc/sudoers.d/builder && \
	chmod a+rx /tmp/termux-packages/scripts/*.sh /tmp/termux-packages/scripts/build/termux_download.sh && \
	su - builder -c "TERMUX_PKGS__BUILD__IS_DOCKER_BUILD='true' /tmp/termux-packages/scripts/setup-ubuntu.sh" && \
	su - builder -c "TERMUX_PKGS__BUILD__IS_DOCKER_BUILD='true' /tmp/termux-packages/scripts/setup-android-sdk.sh" && \
	su - builder -c "TERMUX_PKGS__BUILD__IS_DOCKER_BUILD='true' /tmp/termux-packages/scripts/setup-clang.sh" && \
	su - builder -c "TERMUX_PKGS__BUILD__IS_DOCKER_BUILD='true' /tmp/termux-packages/scripts/setup-mpdec.sh" && \
	# Removed unused parts to make a smaller Docker image:
	apt-get remove -yq --autoremove lsb-release software-properties-common && \
	apt-get clean && \
	rm -rf /var/lib/apt/lists/* && \
	su - builder -c "rm ~/lib/*.zip" && \
	su - builder -c "rm -r ~/.android/cache/"

# Keep in sync with TERMUX_SDK_REVISION and TERMUX_NDK_VERSION in
# scripts/properties.sh (the check below fails the build on drift):
ENV ANDROID_HOME=/home/builder/lib/android-sdk-9123335 \
    NDK=/home/builder/lib/android-ndk-r29

# Verify the toolchain: paths must exist, clang must run, and the wrapper
# for the default TERMUX_PKG_API_LEVEL (24) must link a real binary:
RUN test -d "$ANDROID_HOME/platform-tools" && \
	"$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" --version && \
	echo 'int main(void){return 0;}' > /tmp/cc-test.c && \
	"$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang" /tmp/cc-test.c -o /tmp/cc-test && \
	rm -f /tmp/cc-test.c /tmp/cc-test
USER builder:builder

# We expect this to be mounted with '-v $PWD:/home/builder/termux-packages':
WORKDIR /home/builder/termux-packages
