import Foundation
import Combine
import Supabase

@MainActor
final class AssignmentsViewModel: ObservableObject {
    @Published private(set) var assignments: [Assignment] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    @Published var filter = AssignmentFilter.pending
    @Published var search = ""
    private let client: SupabaseClient
    private var loadGeneration = 0
    private var observationGeneration = UUID()
    init(client: SupabaseClient? = nil) { self.client = client ?? SupabaseService.client }

    func observe(userID: UUID) async {
        let run = UUID()
        observationGeneration = run
        let channel = client.channel("assignments-\(userID)-\(run)")
        let teamChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "asignacion_equipo",
            filter: .eq("perfil_id", value: userID.uuidString)
        )
        let assignmentChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "asignaciones"
        )
        let milestoneChanges = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "hitos_itinerario"
        )

        await load(userID: userID)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                do {
                    try await channel.subscribeWithError()
                    for await _ in teamChanges {
                        guard !Task.isCancelled else { break }
                        await self?.load(userID: userID)
                    }
                } catch { /* Periodic reconciliation remains active. */ }
            }
            group.addTask { [weak self] in
                for await _ in assignmentChanges {
                    guard !Task.isCancelled else { break }
                    await self?.load(userID: userID)
                }
            }
            group.addTask { [weak self] in
                for await _ in milestoneChanges {
                    guard !Task.isCancelled else { break }
                    await self?.load(userID: userID)
                }
            }
            group.addTask { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(10)) } catch { break }
                    await self?.load(userID: userID)
                }
            }
            await group.waitForAll()
        }
        await client.removeChannel(channel)
        if observationGeneration == run {
            observationGeneration = UUID()
        }
    }

    func load(userID: UUID) async {
        loadGeneration += 1
        let generation = loadGeneration
        loading = true
        error = nil
        defer {
            if loadGeneration == generation { loading = false }
        }
        do {
            var result: [Assignment] = []
            var offset = 0
            while true {
                let rows: [AssignmentLink] = try await client.from("asignacion_equipo")
                    .select("asignacion_id,asignaciones(*,hitos_itinerario(*),asignacion_equipo(perfiles(id,nombre_completo,rol)))")
                    .eq("perfil_id", value: userID).order("asignacion_id")
                    .range(from: offset, to: offset + 199).execute().value
                guard !Task.isCancelled, loadGeneration == generation else { return }
                result.append(contentsOf: rows.compactMap(\.asignaciones))
                if rows.count < 200 { break }
                offset += 200
            }
            guard loadGeneration == generation else { return }
            var seen = Set<UUID>()
            assignments = result.filter { seen.insert($0.id).inserted }.sorted {
                if $0.completed != $1.completed { return !$0.completed }
                return ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture)
            }
        } catch {
            guard !Task.isCancelled, loadGeneration == generation else { return }
            self.error = AuthNotice.failure(error).message
        }
    }
    func filtered(at now: Date) -> [Assignment] {
        assignments.filter { item in
            let matches = search.isEmpty || item.titulo.localizedCaseInsensitiveContains(search)
                || (item.ubicacion?.localizedCaseInsensitiveContains(search) == true)
            guard matches else { return false }
            switch filter {
            case .all: return true
            case .pending: return !item.completed && !item.overdue(at: now)
            case .overdue: return item.overdue(at: now)
            case .completed: return item.completed
            }
        }
    }
}
