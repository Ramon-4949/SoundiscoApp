import Foundation
import Combine
import Supabase

@MainActor
final class AssignmentsViewModel: ObservableObject {
    @Published private(set) var assignments: [Assignment] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var pageIndex = 0
    @Published private(set) var hasMore = false
    @Published var search = ""

    private let client: SupabaseClient
    private var query: AssignmentFeedQuery?
    private var loadGeneration = 0
    private var observationGeneration = UUID()
    private var refreshTask: Task<Void, Never>?
    private var failedPage: Int?

    init(client: SupabaseClient? = nil) { self.client = client ?? SupabaseService.client }

    func observe(query selection: AssignmentFeedQuery) async {
        let run = UUID()
        observationGeneration = run
        if query != selection {
            query = selection
            pageIndex = 0
            assignments = []
            hasMore = false
            failedPage = nil
            error = nil
            loading = true
        }
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        guard !Task.isCancelled else { return }
        let channel = client.channel("assignment-page-\(selection.userID)-\(run)")
        let assignmentChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "asignaciones")
        let teamChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "asignacion_equipo")
        let milestoneChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "hitos_itinerario")
        let checkInChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "hitos_colaboradores")
        await refresh()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                do {
                    try await channel.subscribeWithError()
                    for await _ in assignmentChanges {
                        guard !Task.isCancelled else { break }
                        await self?.scheduleRefresh(run: run)
                    }
                } catch { /* Periodic reconciliation remains active. */ }
            }
            group.addTask { [weak self] in
                for await _ in teamChanges {
                    guard !Task.isCancelled else { break }
                    await self?.scheduleRefresh(run: run)
                }
            }
            group.addTask { [weak self] in
                for await _ in milestoneChanges {
                    guard !Task.isCancelled else { break }
                    await self?.scheduleRefresh(run: run)
                }
            }
            group.addTask { [weak self] in
                for await _ in checkInChanges {
                    guard !Task.isCancelled else { break }
                    await self?.scheduleRefresh(run: run)
                }
            }
            group.addTask { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { break }
                    await self?.refreshIfIdle(run: run)
                }
            }
            await group.waitForAll()
        }
        await client.removeChannel(channel)
        if observationGeneration == run {
            refreshTask?.cancel()
            observationGeneration = UUID()
        }
    }

    func refresh() async { await fetch(page: pageIndex) }
    func retry() async { await fetch(page: failedPage ?? pageIndex) }
    func nextPage() async {
        guard hasMore, !loading else { return }
        await fetch(page: pageIndex + 1)
    }
    func previousPage() async {
        guard pageIndex > 0, !loading else { return }
        await fetch(page: pageIndex - 1)
    }

    func pause() {
        observationGeneration = UUID()
        refreshTask?.cancel()
        loadGeneration += 1
        loading = false
    }

    private func fetch(page: Int) async {
        guard let selection = query else { return }
        loadGeneration += 1
        let generation = loadGeneration
        loading = true
        error = nil
        defer { if loadGeneration == generation { loading = false } }
        do {
            let response: AssignmentFeedPage = try await client.rpc("assignments_feed_page",
                params: AssignmentFeedRequest(query: selection, page: page)).execute().value
            guard !Task.isCancelled, loadGeneration == generation, query == selection else { return }
            assignments = response.items.map { item in
                var assignment = item
                assignment.viewingUserID = selection.personalized ? selection.userID : nil
                return assignment
            }
            pageIndex = page
            hasMore = response.hasMore
            failedPage = nil
        } catch {
            guard !Task.isCancelled, loadGeneration == generation, query == selection else { return }
            failedPage = page
            self.error = AuthNotice.failure(error).message
        }
    }

    private func scheduleRefresh(run: UUID) {
        guard observationGeneration == run else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            await self?.refreshIfIdle(run: run)
        }
    }

    private func refreshIfIdle(run: UUID) async {
        guard observationGeneration == run, !loading, !Task.isCancelled else { return }
        await refresh()
    }
}

nonisolated private struct AssignmentFeedPage: Decodable {
    let items: [Assignment]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case items
        case hasMore = "has_more"
    }
}
