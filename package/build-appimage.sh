#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Paths inside the container
QT_INSTALL_DIR="/cache/qtStatic"
GCLC_BUILD_DIR="/cache/gclc-build"
APPDIR="/tmp/AppDir"
OUT_DIR="/out"
SRC_DIR="/app-src"

echo ">>> 1. Installing build dependencies and tools..."
apt-get update && apt-get install -y --no-install-recommends \
  cmake build-essential pkg-config git ca-certificates perl python3 wget file \
  libgl1-mesa-dev libglx-dev libegl1-mesa-dev libglu1-mesa-dev \
  libfreetype6-dev libfontconfig1-dev fontconfig \
  libx11-dev libx11-xcb-dev libxrender-dev libxi-dev libxext-dev \
  libdrm-dev \
  libxkbcommon-dev libxkbcommon-x11-dev \
  libxcb-cursor-dev libxcb-util-dev libxcb-keysyms1-dev \
  libxcb-image0-dev libxcb-shm0-dev libxcb-sync-dev \
  libxcb-xfixes0-dev libxcb-render-util0-dev libxcb-shape0-dev \
  libxcb-randr0-dev libxcb-xkb-dev libxcb-icccm4-dev libxcb-xinerama0-dev

# ---------------------------------------------------------
# Phase 1: Build Static Qt (or reuse existing cache)
# ---------------------------------------------------------
if [ -f "${QT_INSTALL_DIR}/bin/qt-cmake" ]; then
  echo ">>> [Cache Hit] Found static Qt installation at ${QT_INSTALL_DIR}. Skipping Qt build."
else
  echo ">>> [Cache Miss] Compiling static Qt 6.5.2..."

  QT_TMP_BUILD="/tmp/qt-build"
  rm -rf "${QT_TMP_BUILD}"
  mkdir -p "${QT_TMP_BUILD}"
  cd "${QT_TMP_BUILD}"

  git clone --depth 1 -b 6.5.2 https://github.com/qt/qt5.git qt5
  cd qt5
  ./init-repository --module-subset=qtbase

  mkdir -p qtbase/build && cd qtbase/build
  ../configure -static -release -no-pch -nomake tests -nomake examples \
    -no-icu -no-glib \
    -system-freetype -fontconfig \
    -prefix "${QT_INSTALL_DIR}" \
    -xcb-xlib -- -Wno-dev

  cmake --build . --parallel "$(nproc)"
  cmake --install .

  # Cleanup
  cd /
  rm -rf "${QT_TMP_BUILD}"
fi

# ---------------------------------------------------------
# Phase 2: Build GCLC and stage into AppDir
# ---------------------------------------------------------
echo ">>> 2. Building GCLC GUI..."
rm -rf "${APPDIR}"
mkdir -p "${APPDIR}/usr"

# Clean scratch space for source files
GCLC_SRC_SHADOW="/tmp/gclc-src"
rm -rf "${GCLC_SRC_SHADOW}"
mkdir -p "${GCLC_SRC_SHADOW}"

echo ">>> Copying project source files..."
# Copy only the relevant files to a writeable location.
# Needed for generating Version.h
cp "${SRC_DIR}/CMakeLists.txt" "${GCLC_SRC_SHADOW}/"
cp -r "${SRC_DIR}/flatpak" "${GCLC_SRC_SHADOW}/"
cp -r "${SRC_DIR}/source" "${GCLC_SRC_SHADOW}/"

cd "${GCLC_SRC_SHADOW}"

# Generate Version.h inside the writeable source shadow
VERSION_STR="${APP_VERSION:-$(git describe --tags 2>/dev/null || echo "dev")}"
mkdir -p source/Utils
cat <<EOF > source/Utils/Version.h
#pragma once
#define GCLC_VERSION "${VERSION_STR}"
EOF

# Build in the persistent cache directory so incremental compilation still works
mkdir -p "${GCLC_BUILD_DIR}"
"${QT_INSTALL_DIR}/bin/qt-cmake" -B "${GCLC_BUILD_DIR}" -S "${GCLC_SRC_SHADOW}" -DCMAKE_BUILD_TYPE=Release
cmake --build "${GCLC_BUILD_DIR}" --parallel "$(nproc)"
cmake --install "${GCLC_BUILD_DIR}" --prefix "${APPDIR}/usr"
rm -f "${APPDIR}/usr/bin/gclc"

# ---------------------------------------------------------
# Phase 3: Package with linuxdeploy into AppImage
# ---------------------------------------------------------
echo ">>> 3. Packaging into AppImage..."
WORKDIR_DEPLOY="/tmp/linuxdeploy"
mkdir -p "${WORKDIR_DEPLOY}" && cd "${WORKDIR_DEPLOY}"

wget -q https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
chmod +x linuxdeploy-x86_64.AppImage
./linuxdeploy-x86_64.AppImage --appimage-extract > /dev/null

export APPIMAGE_EXTRACT_AND_RUN=1
export VERSION="${VERSION_STR}"

mkdir -p "${OUT_DIR}"
cd "${OUT_DIR}"

"${WORKDIR_DEPLOY}/squashfs-root/AppRun" \
  --appdir "${APPDIR}" \
  --desktop-file "${APPDIR}/usr/share/applications/io.github.ADG_Foundation.gclc.desktop" \
  --executable "${APPDIR}/usr/bin/gclc-gui" \
  --output appimage

# If linuxdeploy created a non-versioned AppImage, rename to ensure consistent naming
if [ -f "GCLC-x86_64.AppImage" ]; then
  mv "GCLC-x86_64.AppImage" "GCLC-${VERSION_STR}-x86_64.AppImage"
fi

# Restore ownership of output and cache files to the host user
if [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
  chown -R "${HOST_UID}:${HOST_GID}" "${OUT_DIR}"
  if [ -d "/cache" ]; then
    chown -R "${HOST_UID}:${HOST_GID}" "/cache" || true
  fi
fi

echo ">>> Build complete! AppImage located in ${OUT_DIR}"
