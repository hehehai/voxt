import Foundation

enum WhisperModelArtifacts {
    static let requiredRelativePaths = [
        "config.json",
        "generation_config.json",
        "MelSpectrogram.mlmodelc",
        "MelSpectrogram.mlmodelc/model.mil",
        "MelSpectrogram.mlmodelc/weights",
        "MelSpectrogram.mlmodelc/weights/weight.bin",
        "AudioEncoder.mlmodelc",
        "AudioEncoder.mlmodelc/model.mil",
        "AudioEncoder.mlmodelc/weights",
        "AudioEncoder.mlmodelc/weights/weight.bin",
        "TextDecoder.mlmodelc",
        "TextDecoder.mlmodelc/model.mil",
        "TextDecoder.mlmodelc/weights",
        "TextDecoder.mlmodelc/weights/weight.bin",
    ]

    static func isValidModelDirectory(_ url: URL, fileManager: FileManager = .default) -> Bool {
        requiredRelativePaths.allSatisfy {
            fileManager.fileExists(atPath: url.appendingPathComponent($0).path)
        }
    }

    static func isCorruptLoadFailure(_ error: Error) -> Bool {
        let message = "\(error.localizedDescription) \(String(describing: error))".lowercased()
        return message.contains("failed to parse ml program")
            || message.contains("invalid or broken model")
            || message.contains("could not open")
            || message.contains("weights/weight.bin")
            || message.contains("error parsing mil model")
    }
}
