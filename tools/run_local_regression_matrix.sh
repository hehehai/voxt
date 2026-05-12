#!/usr/bin/env bash

set -euo pipefail

ROOT="/Users/guanwei/x/doit/Voxt"
PROJECT="$ROOT/Voxt.xcodeproj"
SCHEME="Voxt"
CONFIGURATION="TestDebug"
DESTINATION="platform=macOS"

if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
  echo "Local regression matrix is intended for local machines only." >&2
  exit 1
fi

GROUP="${1:-all}"

run_tests() {
  local label="$1"
  shift
  echo
  echo "==> Running $label"
  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    "$@"
}

run_group_collecting_failures() {
  local overall=0
  local labels=()
  while [[ "$#" -gt 0 ]]; do
    local group_name="$1"
    shift
    labels+=("$group_name")
    set +e
    "$group_name"
    local status=$?
    set -e
    if [[ $status -ne 0 ]]; then
      overall=$status
      echo
      echo "!! Group failed: $group_name (exit $status)"
    fi
  done

  if [[ $overall -ne 0 ]]; then
    echo
    echo "Completed with failures across groups: ${labels[*]}"
    return "$overall"
  fi
}

run_core() {
  run_tests "core pipeline/runtime regression" \
    -only-testing:VoxtTests/TranscriptionCapturePipelineTests \
    -only-testing:VoxtTests/SessionTimingSummarySupportTests \
    -only-testing:VoxtTests/SessionTextIOTests \
    -only-testing:VoxtTests/SessionEndFlowTests \
    -only-testing:VoxtTests/LLMExecutionPlanCompilerTests \
    -only-testing:VoxtTests/EnhancementPromptResolverTests \
    -only-testing:VoxtTests/PromptBuildersTests \
    -only-testing:VoxtTests/AppPromptDefaultsTests \
    -only-testing:VoxtTests/ModelDebugSupportTests
}

run_mlx() {
  run_tests "MLX public fixture regression" \
    -only-testing:VoxtTests/QwenOfficialFixtureASRIntegrationTests \
    -only-testing:VoxtTests/MLXLongFormReplayIntegrationTests \
    -only-testing:VoxtTests/MLXFinalOnlyReplayIntegrationTests \
    -only-testing:VoxtTests/MLXRealtimeReplayIntegrationTests \
    -only-testing:VoxtTests/MLXPipelineMetricsIntegrationTests
}

run_whisper() {
  run_tests "Whisper diagnostic regression" \
    -only-testing:VoxtTests/WhisperOfficialFixtureASRIntegrationTests \
    -only-testing:VoxtTests/WhisperLongFormReplayIntegrationTests \
    -only-testing:VoxtTests/WhisperRealtimeReplayIntegrationTests \
    -only-testing:VoxtTests/WhisperPipelineMetricsIntegrationTests
}

run_installed_matrix() {
  run_tests "installed-model long-form matrix" \
    -only-testing:VoxtTests/InstalledASRLongFormMatrixIntegrationTests
}

case "$GROUP" in
  core)
    run_core
    ;;
  mlx)
    run_mlx
    ;;
  whisper)
    run_whisper
    ;;
  installed)
    run_installed_matrix
    ;;
  diagnostic)
    run_group_collecting_failures run_whisper run_installed_matrix
    ;;
  all)
    run_core
    run_mlx
    ;;
  full)
    run_group_collecting_failures run_core run_mlx run_whisper run_installed_matrix
    ;;
  *)
    echo "Unknown group: $GROUP" >&2
    echo "Usage: $0 [core|mlx|whisper|installed|diagnostic|all|full]" >&2
    exit 2
    ;;
esac
