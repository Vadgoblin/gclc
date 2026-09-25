#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="/app-src"
OUT_DIR="/out"
BUILD_DIR="/tmp/gclc-rpm-build"
GCLC_SRC_SHADOW="/tmp/gclc-src"

echo ">>> 1. Installing build dependencies..."
dnf install -y \
    gcc-c++ \
    cmake \
    make \
    rpm-build \
    file \
    qt6-qtbase-devel \
    hicolor-icon-theme \
    libglvnd-devel

echo ">>> 2. Whitelisting project source files..."
rm -rf "${GCLC_SRC_SHADOW}"
mkdir -p "${GCLC_SRC_SHADOW}"

cp "${SRC_DIR}/CMakeLists.txt" "${GCLC_SRC_SHADOW}/"
if [ -d "${SRC_DIR}/flatpak" ]; then cp -r "${SRC_DIR}/flatpak" "${GCLC_SRC_SHADOW}/"; fi
cp -r "${SRC_DIR}/source" "${GCLC_SRC_SHADOW}/"

cd "${GCLC_SRC_SHADOW}"

# Sanitize version string (RPM forbids leading 'v' and hyphens inside the version field)
RAW_VER="${APP_VERSION:-2024.1.0}"
CLEAN_VER="${RAW_VER#v}"        # strip leading 'v'
CLEAN_VER="${CLEAN_VER//-/_}"    # RPM version field prefers underscores or dots over hyphens

mkdir -p source/Utils
cat <<EOF > source/Utils/Version.h
#pragma once
#define GCLC_VERSION "${CLEAN_VER}"
EOF

echo ">>> 3. Configuring and building GCLC..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

cmake -B "${BUILD_DIR}" -S "${GCLC_SRC_SHADOW}" \
  -DCMAKE_BUILD_TYPE=Release \
  -Dgui=ON \
  -DCPACK_PACKAGE_VERSION="${CLEAN_VER}"

cmake --build "${BUILD_DIR}" --parallel "$(nproc)"

echo ">>> 4. Creating RPM package via CPack..."
cd "${BUILD_DIR}"
cpack -G RPM

mkdir -p "${OUT_DIR}"
cp *.rpm "${OUT_DIR}/"

if [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
  chown -hR "${HOST_UID}:${HOST_GID}" "${OUT_DIR}" || true
fi

echo ">>> Build complete! .rpm package(s) located in ${OUT_DIR}"