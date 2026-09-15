import Foundation
import Combine
import Supabase

@MainActor
final class AssignmentsViewModel: ObservableObject {
    @Published private(set) var assignments: [Assignment] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    @Published var filter = AssignmentFilter.all
    @Published var search = ""
    private let client: SupabaseClient
    init(client: SupabaseClient? = nil) { self.client = client ?? SupabaseService.client }

    func load(userID: UUID) async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            var result: [Assignment] = []
            var offset = 0
            while true {
                let rows: [AssignmentLink] = try await client.from("asignacion_equipo")
                    .select("asignacion_id,asignaciones(*,hitos_itinerario(*))")
                    .eq("perfil_id", value: userID).order("asignacion_id")
                    .range(from: offset, to: offset + 199).execute().value
                guard !Task.isCancelled else { return }
                result.append(contentsOf: rows.compactMap(\.asignaciones))
                if rows.count < 200 { break }
                offset += 200
            }
            var seen = Set<UUID>()
            assignments = result.filter { seen.insert($0.id).inserted }.sorted {
                if $0.completed != $1.completed { return !$0.completed }
                return ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture)
            }
        } catch {
            guard !Task.isCancelled else { return }
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
