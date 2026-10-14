import ContainerBarCore

@MainActor
extension ContainerStore {
    public func dismissActionError() {
        lastActionError = nil
    }

    func performContainerAction(
        id: String,
        progressive: String,
        infinitive: String,
        _ action: (ContainerFetcher) async throws -> Void
    ) async {
        guard !actionInProgress.contains(id) else { return }
        actionInProgress.insert(id)
        defer { actionInProgress.remove(id) }

        logger.info("\(progressive) container: \(id)")

        // The runtime may have started since the last refresh: build the
        // fetcher now rather than failing until the next refresh, and report
        // the mapped init error when it still cannot be built (CB-077).
        if fetcher == nil, case .failure(let error) = initializeFetcher() {
            logger.error("No fetcher available: \(error.localizedDescription)")
            let reason = userFriendlyConnectionErrorMessage(for: error, host: settings.selectedHost)
            lastActionError = ActionError(message: "Unable to \(infinitive) container: \(reason)")
            return
        }

        guard let fetcher else { return }

        do {
            try await action(fetcher)
            lastActionError = nil
            await refresh(force: true)
        } catch {
            logger.error("Failed to \(infinitive) container: \(error.localizedDescription)")
            lastActionError = ActionError(
                message: "Failed to \(infinitive) container: \(error.localizedDescription)"
            )
        }
    }
}
