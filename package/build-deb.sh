#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

SRC_DIR="/app-src"
OUT_DIR="/out"
BUILD_DIR="/tmp/gclc-deb-build"
GCLC_SRC_SHADOW="/tmp/gclc-src"

CLEAN_VER="${APP_VERSION#v}" # Shell built-in, strips leading 'v'
CLEAN_VER="${CLEAN_VER//_/-}" # Replaces '_' with '-'

echo ">>> 1. Installing Debian build tools and Qt6 packages..."
apt-get update && apt-get install -y --no-install-recommends \
  qt6-base-dev libqt6opengl6-dev \
  cmake gcc g++ build-essential \
  libgles2-mesa-dev libgl1-mesa-dev libegl1-mesa-dev libglu1-mesa-dev libglfw3-dev \
  libx11-xcb-dev libxrender-dev libxi-dev libxcb-xinerama0 libglx-dev \
  libxkbcommon-dev libxkbcommon-x11-dev libxcb-xkb-dev \
  file dpkg-dev ca-certificates git

echo ">>> 2. Whitelisting project source files..."
rm -rf "${GCLC_SRC_SHADOW}"
mkdir -p "${GCLC_SRC_SHADOW}"

cp "${SRC_DIR}/CMakeLists.txt" "${GCLC_SRC_SHADOW}/"
if [ -d "${SRC_DIR}/flatpak" ]; then cp -r "${SRC_DIR}/flatpak" "${GCLC_SRC_SHADOW}/"; fi
cp -r "${SRC_DIR}/source" "${GCLC_SRC_SHADOW}/"

cd "${GCLC_SRC_SHADOW}"

VERSION_STR="${APP_VERSION:-$(git describe --tags 2>/dev/null || echo "dev")}"
mkdir -p source/Utils
cat <<EOF > source/Utils/Version.h
#pragma once
#define GCLC_VERSION "${VERSION_STR}"
EOF

echo ">>> 3. Configuring and building GCLC..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

cmake -B "${BUILD_DIR}" -S "${GCLC_SRC_SHADOW}" \
  -DCMAKE_BUILD_TYPE=Release \
  -Dgui=ON \
  -DCPACK_PACKAGE_VERSION="${CLEAN_VER}"

cmake --build "${BUILD_DIR}" --parallel "$(nproc)"

echo ">>> 4. Creating Debian package via CPack..."
cd "${BUILD_DIR}"
cpack -G DEB

mkdir -p "${OUT_DIR}"
cp *.deb "${OUT_DIR}/"

if [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
  chown -hR "${HOST_UID}:${HOST_GID}" "${OUT_DIR}" || true
fi

echo ">>> Build complete! .deb package(s) located in ${OUT_DIR}"