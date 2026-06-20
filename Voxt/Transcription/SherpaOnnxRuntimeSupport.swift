// SherpaOnnxRuntimeSupport.swift
// Provides compile-time sherpa-onnx runtime availability metadata.

import Foundation

enum SherpaOnnxRuntimeSupport {
    nonisolated static var isAvailable: Bool {
        #if SHERPA_ONNX_AVAILABLE
        true
        #else
        false
        #endif
    }

    nonisolated static var unavailableDetail: String? {
        isAvailable
            ? nil
            : String(localized: "Sherpa ONNX runtime is not bundled in this build.")
    }
}
