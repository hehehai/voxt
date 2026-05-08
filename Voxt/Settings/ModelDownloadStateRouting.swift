import Foundation

enum ModelDownloadStateRouting {
    private enum OperationPhase {
        case idle
        case downloading
        case paused
    }

    static func isMLXOperationTarget(
        repo: String,
        activeRepo: String?
    ) -> Bool {
        guard let activeRepo else { return false }
        return MLXModelManager.canonicalModelRepo(repo) == MLXModelManager.canonicalModelRepo(activeRepo)
    }

    static func isMLXDownloading(
        repo: String,
        activeRepo: String?,
        state: MLXModelManager.ModelState
    ) -> Bool {
        isOperationTargetActive(
            isTarget: isMLXOperationTarget(repo: repo, activeRepo: activeRepo),
            phase: operationPhase(for: state),
            expected: .downloading
        )
    }

    static func isMLXPaused(
        repo: String,
        activeRepo: String?,
        state: MLXModelManager.ModelState
    ) -> Bool {
        isOperationTargetActive(
            isTarget: isMLXOperationTarget(repo: repo, activeRepo: activeRepo),
            phase: operationPhase(for: state),
            expected: .paused
        )
    }

    static func isAnotherMLXDownloadActive(
        repo: String,
        activeRepo: String?,
        state: MLXModelManager.ModelState
    ) -> Bool {
        isAnotherOperationActive(
            isTarget: isMLXOperationTarget(repo: repo, activeRepo: activeRepo),
            phase: operationPhase(for: state)
        )
    }

    static func isCustomLLMOperationTarget(
        repo: String,
        managerRepo: String
    ) -> Bool {
        repo == managerRepo
    }

    static func isCustomLLMDownloading(
        repo: String,
        managerRepo: String,
        state: CustomLLMModelManager.ModelState
    ) -> Bool {
        isOperationTargetActive(
            isTarget: isCustomLLMOperationTarget(repo: repo, managerRepo: managerRepo),
            phase: operationPhase(for: state),
            expected: .downloading
        )
    }

    static func isCustomLLMPaused(
        repo: String,
        managerRepo: String,
        state: CustomLLMModelManager.ModelState
    ) -> Bool {
        isOperationTargetActive(
            isTarget: isCustomLLMOperationTarget(repo: repo, managerRepo: managerRepo),
            phase: operationPhase(for: state),
            expected: .paused
        )
    }

    static func isAnotherCustomLLMDownloadActive(
        repo: String,
        managerRepo: String,
        state: CustomLLMModelManager.ModelState
    ) -> Bool {
        isAnotherOperationActive(
            isTarget: isCustomLLMOperationTarget(repo: repo, managerRepo: managerRepo),
            phase: operationPhase(for: state)
        )
    }

    private static func operationPhase(for state: MLXModelManager.ModelState) -> OperationPhase {
        switch state {
        case .downloading:
            return .downloading
        case .paused:
            return .paused
        default:
            return .idle
        }
    }

    private static func operationPhase(for state: CustomLLMModelManager.ModelState) -> OperationPhase {
        switch state {
        case .downloading:
            return .downloading
        case .paused:
            return .paused
        default:
            return .idle
        }
    }

    private static func isOperationTargetActive(
        isTarget: Bool,
        phase: OperationPhase,
        expected: OperationPhase
    ) -> Bool {
        isTarget && phase == expected
    }

    private static func isAnotherOperationActive(
        isTarget: Bool,
        phase: OperationPhase
    ) -> Bool {
        phase == .downloading && !isTarget
    }
}
