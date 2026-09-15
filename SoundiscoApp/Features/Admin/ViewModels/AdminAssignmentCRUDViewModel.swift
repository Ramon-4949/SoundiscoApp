import Foundation
import Combine
import Supabase

@MainActor
final class AdminAssignmentCRUDViewModel: ObservableObject {
    @Published private(set) var isSaving = false
    @Published private(set) var lastSavedAssignment: Asignacion?
    @Published private(set) var errorMessage: String?

    private let client: SupabaseClient

    init(client: SupabaseClient? = nil) {
        self.client = client ?? SupabaseClientFactory.shared
    }

    @discardableResult
    func createAssignment(_ draft: AsignacionDraft) async throws -> Asignacion {
        try validate(draft)
        return try await performSaving {
            let params = CreateAssignmentRPC(
                pAsignacion: AssignmentMutationPayload(draft),
                pEmpleados: draft.empleadosIDs,
                pHitos: milestonePayloads(from: draft.hitos)
            )
            let assignmentID: UUID = try await client
                .rpc("admin_create_assignment", params: params)
                .execute()
                .value
            return try await fetchAssignment(id: assignmentID)
        }
    }

    @discardableResult
    func updateAssignment(id: UUID, with draft: AsignacionDraft) async throws -> Asignacion {
        try validate(draft)
        return try await performSaving {
            let params = UpdateAssignmentRPC(
                pAsignacionID: id,
                pAsignacion: AssignmentMutationPayload(draft),
                pEmpleados: draft.empleadosIDs,
                pHitos: milestonePayloads(from: draft.hitos)
            )
            try await client
                .rpc("admin_update_assignment", params: params)
                .execute()
            return try await fetchAssignment(id: id)
        }
    }

    func deleteAssignment(id: UUID) async throws {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await client
                .rpc("admin_delete_assignment", params: DeleteAssignmentRPC(pAsignacionID: id))
                .execute()
            if lastSavedAssignment?.id == id {
                lastSavedAssignment = nil
            }
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func performSaving(
        operation: () async throws -> Asignacion
    ) async throws -> Asignacion {
        guard !isSaving else { throw AdminDataError.respuestaInvalida }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let assignment = try await operation()
            lastSavedAssignment = assignment
            return assignment
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func fetchAssignment(id: UUID) async throws -> Asignacion {
        try await client
            .from("asignaciones")
            .select(
                "id,tipo_flujo,titulo,ubicacion,nivel_prioridad,instrucciones,estado,fecha_creacion,fecha_limite," +
                "hitos_itinerario(*),asignacion_equipo(perfiles(id,nombre_completo,rol,avatar_url))"
            )
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    private func validate(_ draft: AsignacionDraft) throws {
        guard !draft.titulo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AdminDataError.tituloRequerido
        }
        guard !draft.empleadosIDs.isEmpty else {
            throw AdminDataError.responsableRequerido
        }

        switch draft.tipoFlujo {
        case .operacionesCampo:
            guard draft.ubicacion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw AdminDataError.ubicacionRequerida
            }
            guard !draft.hitos.isEmpty else { throw AdminDataError.itinerarioRequerido }
            try validateMilestones(draft.hitos)
        case .tareaAdministrativa:
            guard draft.ubicacion == nil, draft.hitos.isEmpty else {
                throw AdminDataError.tareaAdministrativaConItinerario
            }
            guard draft.fechaLimite != nil else {
                throw AdminDataError.fechaLimiteRequerida
            }
        }
    }

    private func validateMilestones(_ milestones: [HitoDraft]) throws {
        let ordered = milestones.sorted { $0.orden < $1.orden }
        guard Set(ordered.map(\.orden)).count == ordered.count else {
            throw AdminDataError.secuenciaHitosInvalida
        }

        var foundIncomplete = false
        for milestone in ordered {
            if foundIncomplete && milestone.estado != .bloqueado {
                throw AdminDataError.secuenciaHitosInvalida
            }
            if milestone.estado != .completado {
                foundIncomplete = true
            }
        }
    }

    private func milestonePayloads(from drafts: [HitoDraft]) -> [MilestoneMutationPayload] {
        drafts.sorted { $0.orden < $1.orden }.map(MilestoneMutationPayload.init)
    }
}

private struct AssignmentMutationPayload: Encodable {
    let tipoFlujo: TipoFlujo
    let titulo: String
    let ubicacion: String?
    let prioridad: PrioridadAsignacion
    let instrucciones: String?
    let estado: EstadoAsignacion
    let fechaCreacion: Date
    let fechaLimite: Date?

    init(_ draft: AsignacionDraft) {
        tipoFlujo = draft.tipoFlujo
        titulo = draft.titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        ubicacion = draft.ubicacion
        prioridad = draft.prioridad
        instrucciones = draft.instruccionesOpcionales
        estado = draft.estado
        fechaCreacion = draft.fechaCreacion
        fechaLimite = draft.fechaLimite
    }

    enum CodingKeys: String, CodingKey {
        case tipoFlujo = "tipo_flujo"
        case titulo
        case ubicacion
        case prioridad = "nivel_prioridad"
        case instrucciones
        case estado
        case fechaCreacion = "fecha_creacion"
        case fechaLimite = "fecha_limite"
    }
}

private struct MilestoneMutationPayload: Encodable {
    let id: UUID
    let orden: Int
    let titulo: String
    let horaEstimada: String
    let estado: EstadoHito
    let notasIncidencias: String?

    init(_ draft: HitoDraft) {
        id = draft.id
        orden = draft.orden
        titulo = draft.titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        horaEstimada = draft.horaEstimada
        estado = draft.estado
        notasIncidencias = draft.notasIncidencias
    }

    enum CodingKeys: String, CodingKey {
        case id
        case orden
        case titulo = "descripcion"
        case horaEstimada = "hora_estimada"
        case estado = "estado_hito"
        case notasIncidencias = "notas_incidencias"
    }
}

private struct CreateAssignmentRPC: Encodable {
    let pAsignacion: AssignmentMutationPayload
    let pEmpleados: [UUID]
    let pHitos: [MilestoneMutationPayload]

    enum CodingKeys: String, CodingKey {
        case pAsignacion = "p_asignacion"
        case pEmpleados = "p_empleados"
        case pHitos = "p_hitos"
    }
}

private struct UpdateAssignmentRPC: Encodable {
    let pAsignacionID: UUID
    let pAsignacion: AssignmentMutationPayload
    let pEmpleados: [UUID]
    let pHitos: [MilestoneMutationPayload]

    enum CodingKeys: String, CodingKey {
        case pAsignacionID = "p_asignacion_id"
        case pAsignacion = "p_asignacion"
        case pEmpleados = "p_empleados"
        case pHitos = "p_hitos"
    }
}

private struct DeleteAssignmentRPC: Encodable {
    let pAsignacionID: UUID

    enum CodingKeys: String, CodingKey {
        case pAsignacionID = "p_asignacion_id"
    }
}
