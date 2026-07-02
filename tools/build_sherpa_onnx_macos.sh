#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY_DIR="$ROOT_DIR/ThirdParty/sherpa-onnx"
SOURCE_DIR="$THIRD_PARTY_DIR/src"
REPO_URL="${SHERPA_ONNX_REPO_URL:-https://github.com/k2-fsa/sherpa-onnx.git}"
REPO_REF="${SHERPA_ONNX_REF:-master}"

for tool in git cmake make xcodebuild libtool; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: $tool is required to build sherpa-onnx for macOS." >&2
    if [ "$tool" = "cmake" ]; then
      echo "Install CMake first, for example with: brew install cmake" >&2
    fi
    exit 127
  fi
done

mkdir -p "$THIRD_PARTY_DIR"

if [ ! -d "$SOURCE_DIR/.git" ]; then
  git init "$SOURCE_DIR"
  git -C "$SOURCE_DIR" remote add origin "$REPO_URL"
fi

git -C "$SOURCE_DIR" remote set-url origin "$REPO_URL"
git -C "$SOURCE_DIR" fetch --depth 1 origin "$REPO_REF"
git -C "$SOURCE_DIR" checkout --detach FETCH_HEAD
RESOLVED_REF="$(git -C "$SOURCE_DIR" rev-parse HEAD)"

(
  cd "$SOURCE_DIR"
  rm -rf build-swift-macos/sherpa-onnx.xcframework
  ./build-swift-macos.sh
)

rm -rf "$THIRD_PARTY_DIR/install" "$THIRD_PARTY_DIR/sherpa-onnx.xcframework"
cp -R "$SOURCE_DIR/build-swift-macos/install" "$THIRD_PARTY_DIR/install"
cp -R "$SOURCE_DIR/build-swift-macos/sherpa-onnx.xcframework" "$THIRD_PARTY_DIR/sherpa-onnx.xcframework"

cat <<EOF
sherpa-onnx macOS runtime is ready:
  source: $REPO_URL
  ref: $RESOLVED_REF
  $THIRD_PARTY_DIR/install
  $THIRD_PARTY_DIR/sherpa-onnx.xcframework

To enable it in Voxt, copy:
  Config/SherpaOnnx.local.xcconfig.example
to:
  Config/SherpaOnnx.local.xcconfig
EOF
