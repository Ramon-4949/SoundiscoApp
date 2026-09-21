import Foundation
import Combine
import Supabase

@MainActor
final class AssignmentDetailViewModel: ObservableObject {
    @Published private(set) var assignment: Assignment
    @Published private(set) var isLoading = false
    @Published private(set) var savingMilestoneID: UUID?
    @Published private(set) var errorMessage: String?
    @Published private(set) var confirmations: [MilestoneCheckIn] = []
    @Published private(set) var notes: [AssignmentNote] = []
    @Published private(set) var userID: UUID?
    @Published private(set) var activityLoaded = false

    private let client: SupabaseClient

    init(assignment: Assignment, client: SupabaseClient? = nil) {
        self.assignment = assignment
        self.client = client ?? SupabaseService.client
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let updated: Assignment = try await client
                .from("asignaciones")
                .select("*,hitos_itinerario(*),asignacion_equipo(perfiles(id,nombre_completo,rol))")
                .eq("id", value: assignment.id)
                .single()
                .execute()
                .value
            guard !Task.isCancelled else { return }
            assignment = updated
            let currentUserID = try await client.auth.session.user.id
            userID = currentUserID
            var checks: [MilestoneCheckIn] = []
            var offset = 0
            while true {
                let page: [MilestoneCheckIn] = try await client.from("confirmaciones_hitos")
                    .select().eq("asignacion_id", value: assignment.id)
                    .eq("usuario_id", value: currentUserID)
                    .order("id").range(from: offset, to: offset + 199).execute().value
                checks.append(contentsOf: page)
                if page.count < 200 { break }
                offset += 200
            }
            var loadedNotes: [AssignmentNote] = []
            confirmations = checks
            activityLoaded = true
            offset = 0
            while true {
                let page: [AssignmentNote] = try await client.from("notas_asignacion")
                    .select().eq("asignacion_id", value: assignment.id)
                    .order("created_at", ascending: false).order("id")
                    .range(from: offset, to: offset + 199).execute().value
                loadedNotes.append(contentsOf: page)
                if page.count < 200 { break }
                offset += 200
            }
            confirmations = checks
            notes = loadedNotes
            activityLoaded = true
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = AuthNotice.failure(error).message
        }
    }

    func complete(_ milestone: Milestone) async throws {
        guard savingMilestoneID == nil else { return }
        savingMilestoneID = milestone.id
        errorMessage = nil
        defer { savingMilestoneID = nil }

        do {
            let parameters = [
                "p_hito_id": milestone.id.uuidString
            ]
            try await client
                .rpc("check_in_milestone", params: parameters)
                .execute()
            let currentUserID = try await client.auth.session.user.id
            let saved: MilestoneCheckIn = try await client.from("confirmaciones_hitos")
                .select().eq("hito_id", value: milestone.id)
                .eq("usuario_id", value: currentUserID).single().execute().value
            userID = currentUserID
            confirmations.removeAll { $0.hito_id == milestone.id }
            confirmations.append(saved)
            await reload()
        } catch {
            errorMessage = AuthNotice.failure(error).message
            throw error
        }
    }

    func clearError() {
        errorMessage = nil
    }
    func confirmation(for milestone: Milestone) -> MilestoneCheckIn? {
        confirmations.first { $0.hito_id == milestone.id && $0.usuario_id == userID }
    }

    func addNote(id: UUID, content: String) async throws {
        try await client.rpc("add_assignment_note", params: [
            "p_id": id.uuidString,
            "p_asignacion_id": assignment.id.uuidString,
            "p_contenido": content
        ]).execute()
        await reload()
    }
}
