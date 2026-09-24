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
                .select("*,hitos_itinerario(*,hitos_colaboradores(*,perfiles(id,nombre_completo,rol))),asignacion_supervisores(usuario_id),asignacion_equipo(perfiles(id,nombre_completo,rol))")
                .eq("id", value: assignment.id)
                .single()
                .execute()
                .value
            guard !Task.isCancelled else { return }
            assignment = updated
            let currentUserID = try await client.auth.session.user.id
            userID = currentUserID
            assignment.viewingUserID = currentUserID
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
        if let reason = checkInBlock(milestone, at: .now) {
            throw AdminDataError.campoInvalido(reason)
        }
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

    func checkInBlock(_ milestone: Milestone, at now: Date) -> String? {
        guard activityLoaded, let userID else { return "Cargando tu participación…" }
        let personal = assignment.milestones.filter {
            ($0.hitos_colaboradores ?? []).contains { $0.usuario_id == userID }
        }
        guard let index = personal.firstIndex(where: { $0.id == milestone.id }) else {
            return "No estás asignado a este hito."
        }
        if (milestone.hitos_colaboradores ?? []).contains(where: { $0.usuario_id == userID && $0.confirmado }) {
            return "Confirmado"
        }
        guard let deadline = personal.last.flatMap({ AgendaDate.parse($0.fecha_programada) }) else {
            return "El hito no tiene fecha límite."
        }
        if now > deadline { return "Tu plazo final venció. No puedes confirmar hitos pendientes." }
        if personal[..<index].contains(where: { h in
            !(h.hitos_colaboradores ?? []).contains { $0.usuario_id == userID && $0.confirmado }
        }) { return "Confirma primero tu hito anterior." }
        return nil
    }

    func observe() async {
        let channel = client.channel("milestone-detail-\(assignment.id)-\(UUID())")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "hitos_colaboradores")
        let milestones = channel.postgresChange(AnyAction.self, schema: "public", table: "hitos_itinerario",
            filter: .eq("asignacion_id", value: assignment.id.uuidString))
        await reload()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                do {
                    try await channel.subscribeWithError()
                    for await _ in changes {
                        guard !Task.isCancelled else { break }
                        await self?.reload()
                    }
                } catch { /* Periodic reconciliation below also handles reconnects. */ }
            }
            group.addTask { [weak self] in
                for await _ in milestones {
                    guard !Task.isCancelled else { break }
                    await self?.reload()
                }
            }
            group.addTask { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(10)) } catch { break }
                    await self?.reload()
                }
            }
            await group.waitForAll()
        }
        await client.removeChannel(channel)
    }
    func confirmation(for milestone: Milestone) -> MilestoneCheckIn? {
        confirmations.first { $0.hito_id == milestone.id && $0.usuario_id == userID }
    }

    func addNote(id: UUID, content: String) async throws {
        if let error = FormValidation.text(content, field: "La nota", minimum: 3, maximum: 4000) {
            throw AdminDataError.campoInvalido(error)
        }
        try await client.rpc("add_assignment_note", params: [
            "p_id": id.uuidString,
            "p_asignacion_id": assignment.id.uuidString,
            "p_contenido": content
        ]).execute()
        await reload()
    }
}
