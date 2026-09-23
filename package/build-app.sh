#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update && apt-get install -y --no-install-recommends \
  cmake build-essential pkg-config git \
  libgl1-mesa-dev libglx-dev libegl1-mesa-dev libglu1-mesa-dev \
  libfreetype6-dev libfontconfig1-dev fontconfig \
  libx11-dev libx11-xcb-dev libxrender-dev libxi-dev libxext-dev \
  libdrm-dev \
  libxkbcommon-dev libxkbcommon-x11-dev \
  libxcb-cursor-dev libxcb-util-dev libxcb-keysyms1-dev \
  libxcb-image0-dev libxcb-shm0-dev libxcb-sync-dev \
  libxcb-xfixes0-dev libxcb-render-util0-dev libxcb-shape0-dev \
  libxcb-randr0-dev libxcb-xkb-dev libxcb-icccm4-dev libxcb-xinerama0-dev


QT_DIR="/qtStatic"
SRC_DIR="/app-src"
BUILD_DIR="/build-tmp"
APPDIR="/out"


mkdir -p "${BUILD_DIR}"
mkdir -p "${APPDIR}/usr"

# /app-src is read-only (:ro) but Version.h needs to be modified
# copy source code to a writable temporary workspace
cp -r "${SRC_DIR}/." "${BUILD_DIR}/src"
cd "${BUILD_DIR}/src"


VERSION_STR="${APP_VERSION:-$(git describe --tags 2>/dev/null || echo "dev")}"
mkdir -p source/Utils
cat <<EOF > source/Utils/Version.h
#pragma once
#define GCLC_VERSION "${VERSION_STR}"
EOF


"${QT_DIR}/bin/qt-cmake" -B "${BUILD_DIR}/cmake-build" -S . -DCMAKE_BUILD_TYPE=Release
cmake --build "${BUILD_DIR}/cmake-build" --parallel "$(nproc)"

cmake --install "${BUILD_DIR}/cmake-build" --prefix "${APPDIR}/usr"

if [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
  chown -R "${HOST_UID}:${HOST_GID}" "${APPDIR}"
fi
