// MLXModelLifecycleMemoryIntegrationTests.swift
// Runs opt-in, same-process lifecycle stress tests against an installed MLX ASR model.

import Darwin
import MLX
import XCTest
@testable import Voxt

@MainActor
final class MLXModelLifecycleMemoryIntegrationTests: XCTestCase {
    private struct MemorySample {
        let cycle: Int
        let physicalFootprint: UInt64
        let mlxActive: Int
        let mlxCache: Int
        let mallocPressureRelief: Int
    }

    func testRepeatedInferenceAndReleaseReportsStableIdleMemory() async throws {
        try ModelTestGate.requireEnabled("MLX model lifecycle memory integration test")

        let environment = ProcessInfo.processInfo.environment
        let modelRoot = environment["VOXT_MODEL_STORAGE_ROOT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let modelRoot, !modelRoot.isEmpty else {
            throw XCTSkip("Set VOXT_MODEL_STORAGE_ROOT to an installed Voxt model directory.")
        }

        let repo = environment["VOXT_MEMORY_STRESS_MODEL_REPO"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? "mlx-community/Qwen3-ASR-1.7B-4bit"
        let cycleCount = max(Int(environment["VOXT_MEMORY_STRESS_CYCLES"] ?? "") ?? 3, 2)
        let loadOnly = environment["VOXT_MEMORY_STRESS_LOAD_ONLY"] == "1"
        let settleSeconds = max(Double(environment["VOXT_MEMORY_STRESS_SETTLE_SECONDS"] ?? "") ?? 0, 0)
        let holdSeconds = max(Double(environment["VOXT_MEMORY_STRESS_HOLD_SECONDS"] ?? "") ?? 0, 0)
        let fixtureURL = try qwenFixtureURL(named: "qwen_audio_short_zh_chongqing.wav")

        configureModelStorageRoot(modelRoot)
        let probeManager = MLXModelManager(modelRepo: repo)
        guard probeManager.isModelDownloaded(repo: repo) else {
            throw XCTSkip("The requested memory-stress model is not installed: \(repo)")
        }
        await probeManager.shutdownForApplicationTermination()

        let baseline = settledMemorySample(cycle: 0)
        report(baseline, repo: repo)

        var allSamples = [baseline]
        var samples: [MemorySample] = []
        for cycle in 1...cycleCount {
            let transcript = try await runAndReleaseCycle(
                repo: repo,
                fixtureURL: fixtureURL,
                loadOnly: loadOnly
            )
            if !loadOnly {
                XCTAssertFalse(
                    transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "The real-model cycle should complete inference before measuring cleanup."
                )
            }
            if settleSeconds > 0 {
                try await Task.sleep(for: .seconds(settleSeconds))
            }

            let sample = settledMemorySample(cycle: cycle)
            samples.append(sample)
            allSamples.append(sample)
            report(sample, repo: repo)
        }

        let first = try XCTUnwrap(samples.first)
        let last = try XCTUnwrap(samples.last)
        let footprintGrowth = Int64(last.physicalFootprint) - Int64(first.physicalFootprint)
        let activeGrowth = last.mlxActive - first.mlxActive
        print(
            "MLX_LIFECYCLE_STRESS summary repo=\(repo) cycles=\(cycleCount) "
                + "idleFootprintGrowthBytes=\(footprintGrowth) mlxActiveGrowthBytes=\(activeGrowth)"
        )
        try writeReportIfRequested(
            samples: allSamples,
            repo: repo,
            footprintGrowth: footprintGrowth,
            activeGrowth: activeGrowth
        )
        if holdSeconds > 0 {
            print(
                "MLX_LIFECYCLE_STRESS holding pid=\(ProcessInfo.processInfo.processIdentifier) "
                    + "seconds=\(holdSeconds)"
            )
            try await Task.sleep(for: .seconds(holdSeconds))
        }

        XCTAssertLessThanOrEqual(
            activeGrowth,
            1024,
            "MLX active allocations should not accumulate across completed model lifecycles."
        )
    }

    private func runAndReleaseCycle(
        repo: String,
        fixtureURL: URL,
        loadOnly: Bool
    ) async throws -> String {
        let manager = MLXModelManager(modelRepo: repo)
        let transcriber = MLXTranscriber(modelManager: manager)

        do {
            let transcript: String
            if loadOnly {
                manager.beginActiveUse()
                defer { manager.endActiveUse() }
                _ = try await manager.loadModel()
                transcript = ""
            } else {
                transcript = try await transcriber.transcribeAudioFile(fixtureURL)
            }
            await transcriber.shutdownForApplicationTermination()
            _ = transcriber.releaseIdleResources()
            await manager.shutdownForApplicationTermination()
            XCTAssertFalse(manager.hasLoadedModel)
            XCTAssertFalse(manager.hasPendingModelLoad)
            return transcript
        } catch {
            await transcriber.shutdownForApplicationTermination()
            _ = transcriber.releaseIdleResources()
            await manager.shutdownForApplicationTermination()
            throw error
        }
    }

    private func settledMemorySample(cycle: Int) -> MemorySample {
        let reclaimedBytes = IdleMemoryReclamationSupport.releaseAllocatorCaches()
        let mlx = Memory.snapshot()
        return MemorySample(
            cycle: cycle,
            physicalFootprint: physicalFootprintBytes(),
            mlxActive: mlx.activeMemory,
            mlxCache: mlx.cacheMemory,
            mallocPressureRelief: reclaimedBytes
        )
    }

    private func physicalFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    reboundPointer,
                    &count
                )
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    private func report(_ sample: MemorySample, repo: String) {
        print(reportLine(sample, repo: repo))
    }

    private func reportLine(_ sample: MemorySample, repo: String) -> String {
        "MLX_LIFECYCLE_STRESS cycle=\(sample.cycle) repo=\(repo) "
            + "physicalFootprintBytes=\(sample.physicalFootprint) "
            + "mlxActiveBytes=\(sample.mlxActive) mlxCacheBytes=\(sample.mlxCache) "
            + "mallocPressureReliefBytes=\(sample.mallocPressureRelief)"
    }

    private func writeReportIfRequested(
        samples: [MemorySample],
        repo: String,
        footprintGrowth: Int64,
        activeGrowth: Int
    ) throws {
        guard let reportPath = ProcessInfo.processInfo.environment["VOXT_MEMORY_STRESS_REPORT_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        else { return }

        let summary = "MLX_LIFECYCLE_STRESS summary pid=\(ProcessInfo.processInfo.processIdentifier) "
            + "repo=\(repo) cycles=\(samples.count - 1) "
            + "idleFootprintGrowthBytes=\(footprintGrowth) mlxActiveGrowthBytes=\(activeGrowth)"
        let contents = (samples.map { reportLine($0, repo: repo) } + [summary])
            .joined(separator: "\n") + "\n"
        try contents.write(
            to: URL(fileURLWithPath: reportPath),
            atomically: true,
            encoding: .utf8
        )
    }

    private func configureModelStorageRoot(_ modelRoot: String) {
        let defaults = UserDefaults.standard
        let previousPath = defaults.string(forKey: AppPreferenceKey.modelStorageRootPath)
        let previousBookmark = defaults.data(forKey: AppPreferenceKey.modelStorageRootBookmark)

        defaults.set(modelRoot, forKey: AppPreferenceKey.modelStorageRootPath)
        defaults.removeObject(forKey: AppPreferenceKey.modelStorageRootBookmark)
        ModelStorageDirectoryManager.resetForTesting()

        addTeardownBlock {
            if let previousPath {
                defaults.set(previousPath, forKey: AppPreferenceKey.modelStorageRootPath)
            } else {
                defaults.removeObject(forKey: AppPreferenceKey.modelStorageRootPath)
            }
            if let previousBookmark {
                defaults.set(previousBookmark, forKey: AppPreferenceKey.modelStorageRootBookmark)
            } else {
                defaults.removeObject(forKey: AppPreferenceKey.modelStorageRootBookmark)
            }
            ModelStorageDirectoryManager.resetForTesting()
        }
    }

    private func qwenFixtureURL(named fileName: String) throws -> URL {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Audio/qwen-official", isDirectory: true)
            .appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Missing official audio fixture: \(fileName)")
        }
        return url
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
