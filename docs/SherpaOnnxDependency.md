# Sherpa ONNX Dependency Policy

Voxt can use `sherpa-onnx` for local offline ASR through its C API. The default repository build does not bundle the runtime; the code path is compiled only when `SHERPA_ONNX_AVAILABLE` is enabled locally.

## Local Runtime Setup

1. Build the upstream macOS runtime:

   ```bash
   tools/build_sherpa_onnx_macos.sh
   ```

   This requires `git`, `cmake`, `make`, `xcodebuild`, and `libtool` on the local machine. If CMake is missing, install it first, for example with `brew install cmake`.

2. Enable the local Xcode settings:

   ```bash
   cp Config/SherpaOnnx.local.xcconfig.example Config/SherpaOnnx.local.xcconfig
   ```

3. Build Voxt with the shared scheme.

The script clones `k2-fsa/sherpa-onnx`, runs upstream `build-swift-macos.sh`, and places the local artifacts under `ThirdParty/sherpa-onnx/`. That directory and `Config/SherpaOnnx.local.xcconfig` are gitignored.

## Model Policy

- FireRed uses the official sherpa-onnx FireRed ASR 2 CTC int8 package.
- FunASR Nano uses the official sherpa-onnx FunASR Nano int8 package.
- FireRed 2 Mini and FunASR Nano are hidden compatibility models. Existing installations and stored selections remain supported, but neither model is offered as a new default download.
- Model downloads are managed by Voxt and stored under the same configurable model storage root as other local models.

## Integration Notes

- `Voxt/Voxt-SherpaOnnx-Bridging-Header.h` imports `sherpa-onnx/c-api/c-api.h`.
- `Config/SherpaOnnx.local.xcconfig.example` adds the header and library search paths, links `libsherpa-onnx`, `libonnxruntime`, `libc++`, and defines `SHERPA_ONNX_AVAILABLE`.
- The upstream Swift macOS build currently produces static libraries, including `libonnxruntime.a`, so `SHERPA_ONNX_COPY_RUNTIME` defaults to `NO`.
- The Voxt app target still has a no-op-by-default build phase that can copy `libonnxruntime*.dylib` into the app bundle if a future dynamic runtime package is used and `SHERPA_ONNX_COPY_RUNTIME=YES`.

## Release Rule

Do not commit generated `sherpa-onnx` binaries into this repository. If Voxt ships sherpa-onnx in a release, pin an upstream sherpa-onnx commit or release, archive the exact runtime artifact in the release process, and run real FireRed and FunASR Nano recognition smoke tests before publishing.
