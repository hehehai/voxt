#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/tmp/OmniVAD-Kit"
BUILD_DIR="${SRC_DIR}/build-voxt"
REPO_URL="https://github.com/lifeiteng/OmniVAD-Kit.git"

if [ ! -d "${SRC_DIR}/.git" ]; then
  rm -rf "${SRC_DIR}"
  git clone --depth 1 "${REPO_URL}" "${SRC_DIR}"
fi

cmake -S "${SRC_DIR}" \
  -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-15.0}"

cmake --build "${BUILD_DIR}" --config Release -j"$(sysctl -n hw.ncpu)"

mkdir -p "${ROOT_DIR}/Voxt/Frameworks" "${ROOT_DIR}/Voxt/Resources/OmniVAD"
cp -f "${BUILD_DIR}/libomnivad.dylib" "${ROOT_DIR}/Voxt/Frameworks/libomnivad.dylib"
cp -f "${SRC_DIR}/models/vad.omnivad" "${ROOT_DIR}/Voxt/Resources/OmniVAD/vad.omnivad"
cp -f "${SRC_DIR}/models/stream-vad.omnivad" "${ROOT_DIR}/Voxt/Resources/OmniVAD/stream-vad.omnivad"
cp -f "${SRC_DIR}/models/aed.omnivad" "${ROOT_DIR}/Voxt/Resources/OmniVAD/aed.omnivad"
cp -f "${SRC_DIR}/LICENSE" "${ROOT_DIR}/Voxt/Resources/OmniVAD/LICENSE-OmniVAD-Kit.txt"

otool -L "${ROOT_DIR}/Voxt/Frameworks/libomnivad.dylib"
