import Foundation
import Combine
import Supabase

@MainActor
final class AssignmentDetailViewModel: ObservableObject {
    @Published private(set) var assignment: Assignment
    @Published private(set) var isLoading = false
    @Published private(set) var savingMilestoneID: UUID?
    @Published private(set) var errorMessage: String?

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
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = AuthNotice.failure(error).message
        }
    }

    func complete(_ milestone: Milestone, notes: String?) async throws {
        guard savingMilestoneID == nil else { return }
        guard !assignment.overdue(at: .now) else {
            let error = AssignmentCompletionError.expired
            errorMessage = error.localizedDescription
            throw error
        }
        savingMilestoneID = milestone.id
        errorMessage = nil
        defer { savingMilestoneID = nil }

        do {
            let parameters = [
                "p_hito_id": milestone.id.uuidString,
                "p_notas": notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            ]
            try await client
                .rpc("employee_complete_milestone", params: parameters)
                .execute()
            await reload()
        } catch {
            errorMessage = AuthNotice.failure(error).message
            throw error
        }
    }

    func clearError() {
        errorMessage = nil
    }
}

private enum AssignmentCompletionError: LocalizedError {
    case expired

    var errorDescription: String? {
        "La fecha límite de esta asignación ya venció. El checklist está bloqueado."
    }
}
