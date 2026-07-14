// SherpaOnnxModelSupport.swift
// Provides sherpa-onnx ASR model catalog metadata.

import Foundation

enum SherpaOnnxModelKind: String, Hashable, Sendable {
    case fireRedASRCTC
    case funASRNano
}

enum SherpaOnnxModelVisibility: String, Hashable, Sendable {
    case visible
    case hiddenSupport
}

nonisolated struct SherpaOnnxModelID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    let rawValue: String

    var id: String { rawValue }

    nonisolated init(rawValue: String) {
        self.rawValue = SherpaOnnxModelCatalog.canonicalModelID(rawValue)
    }
}

struct SherpaOnnxModelOption: Identifiable, Hashable, Sendable {
    let id: SherpaOnnxModelID
    let title: String
    let description: String
    let kind: SherpaOnnxModelKind
    let downloadSources: [ModelDownloadSourceCandidate]
    let archiveBytes: Int64
    let estimatedDiskBytes: Int64
    let extractedDirectoryName: String
    let requiredRelativePaths: [String]
    let ratingText: String
    let tagKeys: [String]
    let visibility: SherpaOnnxModelVisibility

    var downloadURL: URL {
        downloadSources[0].url
    }
}

enum SherpaOnnxModelCatalog {
    nonisolated private static let fireRedModelIDRawValue = "fire-red-asr-v2-onnx"
    nonisolated private static let funASRNanoModelIDRawValue = "funasr-nano-int8"

    nonisolated static let fireRedModelID = SherpaOnnxModelID(rawValue: fireRedModelIDRawValue)
    nonisolated static let funASRNanoModelID = SherpaOnnxModelID(rawValue: funASRNanoModelIDRawValue)
    nonisolated static let defaultModelID = fireRedModelID

    nonisolated private static let legacyModelIDMap: [String: String] = [
        "fire-red-asr-zh-en": fireRedModelIDRawValue,
        "firered-asr2-ctc-int8": fireRedModelIDRawValue,
        "sherpa-onnx-fire-red-asr2-ctc-zh_en-int8-2026-02-25": fireRedModelIDRawValue,
        "sherpa-onnx-funasr-nano-int8-2025-12-30": funASRNanoModelIDRawValue,
    ]

    nonisolated static let legacyFireRedMLXRepos: Set<String> = [
        "mlx-community/FireRedASR2",
        "mlx-community/FireRedASR2-AED-mlx",
    ]

    nonisolated static let allModels: [SherpaOnnxModelOption] = [
        SherpaOnnxModelOption(
            id: fireRedModelID,
            title: "FireRed 2 Mini",
            description: "Sherpa FireRed 2 Mini CTC int8 model for Chinese and English offline transcription.",
            kind: .fireRedASRCTC,
            downloadSources: [
                ModelDownloadSourceCandidate(
                    id: "github",
                    displayName: "GitHub",
                    url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-fire-red-asr2-ctc-zh_en-int8-2026-02-25.tar.bz2")!
                ),
                ModelDownloadSourceCandidate(
                    id: "modelscope",
                    displayName: "ModelScope",
                    url: URL(string: "https://modelscope.cn/models/csukuangfj/asr-models/resolve/master/sherpa-onnx-fire-red-asr2-ctc-zh_en-int8-2026-02-25.tar.bz2")!
                ),
            ],
            archiveBytes: 520_516_278,
            estimatedDiskBytes: 540_000_000,
            extractedDirectoryName: "sherpa-onnx-fire-red-asr2-ctc-zh_en-int8-2026-02-25",
            requiredRelativePaths: ["model.int8.onnx", "tokens.txt"],
            ratingText: "4.8",
            tagKeys: ["Local", "Multilingual", "Accurate", "Compact"],
            visibility: .hiddenSupport
        ),
        SherpaOnnxModelOption(
            id: funASRNanoModelID,
            title: "FunASR Nano",
            description: "Sherpa FunASR Nano int8 model with a compact encoder and Qwen tokenizer assets.",
            kind: .funASRNano,
            downloadSources: [
                ModelDownloadSourceCandidate(
                    id: "github",
                    displayName: "GitHub",
                    url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-funasr-nano-int8-2025-12-30.tar.bz2")!
                ),
                ModelDownloadSourceCandidate(
                    id: "modelscope",
                    displayName: "ModelScope",
                    url: URL(string: "https://modelscope.cn/models/csukuangfj/asr-models/resolve/master/sherpa-onnx-funasr-nano-int8-2025-12-30.tar.bz2")!
                ),
            ],
            archiveBytes: 841_730_611,
            estimatedDiskBytes: 948_000_000,
            extractedDirectoryName: "sherpa-onnx-funasr-nano-int8-2025-12-30",
            requiredRelativePaths: [
                "encoder_adaptor.int8.onnx",
                "llm.int8.onnx",
                "embedding.int8.onnx",
                "Qwen3-0.6B",
            ],
            ratingText: "4.5",
            tagKeys: ["Local", "Multilingual", "Fast", "Compact"],
            visibility: .hiddenSupport
        ),
    ]

    nonisolated static let availableModels = allModels.filter { $0.visibility == .visible }
    nonisolated static let supportedModels = allModels

    nonisolated static func displayModels(including modelIDs: Set<SherpaOnnxModelID>) -> [SherpaOnnxModelOption] {
        allModels.filter { model in
            model.visibility == .visible || modelIDs.contains(model.id)
        }
    }

    nonisolated static func canonicalModelID(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return legacyModelIDMap[trimmed] ?? trimmed
    }

    nonisolated static func option(for id: SherpaOnnxModelID) -> SherpaOnnxModelOption {
        allModels.first(where: { $0.id == id }) ?? allModels[0]
    }

    nonisolated static func option(forRawID rawID: String) -> SherpaOnnxModelOption {
        option(for: SherpaOnnxModelID(rawValue: rawID))
    }

    nonisolated static func isLegacyFireRedMLXRepo(_ repo: String) -> Bool {
        legacyFireRedMLXRepos.contains(MLXModelManager.canonicalModelRepo(repo))
            || legacyFireRedMLXRepos.contains(repo)
    }

    nonisolated static func displayTitle(for id: SherpaOnnxModelID) -> String {
        option(for: id).title
    }

    nonisolated static func ratingText(for id: SherpaOnnxModelID) -> String {
        option(for: id).ratingText
    }

    nonisolated static func catalogTagKeys(for id: SherpaOnnxModelID) -> [String] {
        option(for: id).tagKeys
    }

    nonisolated static func sizeText(for id: SherpaOnnxModelID) -> String {
        MLXModelStorageSupport.formatByteCount(option(for: id).archiveBytes)
    }
}

enum SherpaOnnxModelStorageSupport {
    nonisolated static func modelDirectory(for id: SherpaOnnxModelID, rootDirectory: URL) -> URL {
        rootDirectory
            .appendingPathComponent("sherpa-onnx", isDirectory: true)
            .appendingPathComponent(id.rawValue, isDirectory: true)
    }

    nonisolated static func downloadDirectory(for id: SherpaOnnxModelID, rootDirectory: URL) -> URL {
        rootDirectory
            .appendingPathComponent("sherpa-onnx", isDirectory: true)
            .appendingPathComponent("\(id.rawValue)-download", isDirectory: true)
    }

    nonisolated static func archiveURL(for id: SherpaOnnxModelID, rootDirectory: URL) -> URL {
        downloadDirectory(for: id, rootDirectory: rootDirectory)
            .appendingPathComponent("\(id.rawValue).tar.bz2")
    }

    nonisolated static func isModelDirectoryValid(
        _ directory: URL,
        option: SherpaOnnxModelOption,
        fileManager: FileManager = .default
    ) -> Bool {
        option.requiredRelativePaths.allSatisfy { relativePath in
            fileManager.fileExists(atPath: directory.appendingPathComponent(relativePath).path)
        }
    }
}
