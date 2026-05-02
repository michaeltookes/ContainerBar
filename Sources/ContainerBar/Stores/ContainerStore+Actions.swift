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

        guard let fetcher else {
            logger.error("No fetcher available")
            lastActionError = ActionError(
                message: "Unable to \(infinitive) container: Docker connection is not configured"
            )
            return
        }

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
