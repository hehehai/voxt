import Foundation

enum ModelDownloadStateRouting {
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
        guard isMLXOperationTarget(repo: repo, activeRepo: activeRepo) else { return false }
        if case .downloading = state {
            return true
        }
        return false
    }

    static func isMLXPaused(
        repo: String,
        activeRepo: String?,
        state: MLXModelManager.ModelState
    ) -> Bool {
        guard isMLXOperationTarget(repo: repo, activeRepo: activeRepo) else { return false }
        if case .paused = state {
            return true
        }
        return false
    }

    static func isAnotherMLXDownloadActive(
        repo: String,
        activeRepo: String?,
        state: MLXModelManager.ModelState
    ) -> Bool {
        guard case .downloading = state else { return false }
        return !isMLXOperationTarget(repo: repo, activeRepo: activeRepo)
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
        guard isCustomLLMOperationTarget(repo: repo, managerRepo: managerRepo) else { return false }
        if case .downloading = state {
            return true
        }
        return false
    }

    static func isCustomLLMPaused(
        repo: String,
        managerRepo: String,
        state: CustomLLMModelManager.ModelState
    ) -> Bool {
        guard isCustomLLMOperationTarget(repo: repo, managerRepo: managerRepo) else { return false }
        if case .paused = state {
            return true
        }
        return false
    }

    static func isAnotherCustomLLMDownloadActive(
        repo: String,
        managerRepo: String,
        state: CustomLLMModelManager.ModelState
    ) -> Bool {
        guard case .downloading = state else { return false }
        return !isCustomLLMOperationTarget(repo: repo, managerRepo: managerRepo)
    }
}
