#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
DEST_DIR="${QT_INSTALL_PREFIX:-/out}"

apt-get update && apt-get install -y --no-install-recommends \
  pkg-config cmake build-essential gcc g++ git ca-certificates perl python3 \
  libgl1-mesa-dev libglx-dev libegl1-mesa-dev libglu1-mesa-dev \
  libfreetype6-dev libfontconfig1-dev fontconfig \
  libx11-dev libx11-xcb-dev libxrender-dev libxi-dev libxext-dev \
  libdrm-dev \
  libxkbcommon-dev libxkbcommon-x11-dev \
  libxcb-cursor-dev libxcb-util-dev libxcb-keysyms1-dev \
  libxcb-image0-dev libxcb-shm0-dev libxcb-sync-dev \
  libxcb-xfixes0-dev libxcb-render-util0-dev libxcb-shape0-dev \
  libxcb-randr0-dev libxcb-xkb-dev libxcb-icccm4-dev libxcb-xinerama0-dev

mkdir -p /qt-source && cd /qt-source
git clone --depth 1 -b 6.5.2 https://github.com/qt/qt5.git .
./init-repository --module-subset=qtbase

cd qtbase
mkdir -p build && cd build
../configure -static -release -no-pch -nomake tests -nomake examples \
  -no-icu -no-glib \
  -system-freetype -fontconfig \
  -prefix "${DEST_DIR}" \
  -xcb-xlib -- -Wno-dev

cmake --build . --parallel "$(nproc)"
cmake --install .

# Restore host permissions if UID/GID were passed
if [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
  chown -R "${HOST_UID}:${HOST_GID}" "${DEST_DIR}"
fi
