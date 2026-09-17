#!/bin/bash
# Focused resource-safety regression. Requires the same Xcode as the main CI job.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]] || ! command -v xcodebuild >/dev/null 2>&1; then
  echo "macOS with Xcode is required; no tests were run." >&2
  exit 2
fi

args=(-onlyUsePackageVersionsFromResolvedFile -skipPackagePluginValidation)
if [[ -n "${SPM_CACHE_PATH:-}" ]]; then
  args+=(-packageCachePath "$SPM_CACHE_PATH" -disablePackageRepositoryCache)
fi
if [[ -n "${SPM_CLONE_PATH:-}" ]]; then
  args+=(-clonedSourcePackagesDirPath "$SPM_CLONE_PATH")
fi
xcodebuild test \
  -project Voxt.xcodeproj -scheme Voxt -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:VoxtTests/MeetingFileResourceSafetyTests \
  -only-testing:VoxtTests/MeetingPCM16AudioSampleSourceTests \
  -only-testing:VoxtTests/MeetingFileTaskQueueTests \
  -only-testing:VoxtTests/MeetingImportedAudioFileTests \
  -only-testing:VoxtTests/MeetingLocalInferenceCoordinatorTests \
  -only-testing:VoxtTests/MeetingHistoryDurabilityTests \
  -only-testing:VoxtTests/MeetingTranscriptAssemblyTests \
  "${args[@]}" "$@" CODE_SIGNING_ALLOWED=NO
