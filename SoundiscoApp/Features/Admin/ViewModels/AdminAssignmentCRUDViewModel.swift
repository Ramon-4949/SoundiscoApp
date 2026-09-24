import Foundation
import Combine
import Supabase

@MainActor
final class AdminAssignmentCRUDViewModel: ObservableObject {
    @Published private(set) var isSaving = false
    @Published private(set) var lastSavedAssignment: Asignacion?
    @Published private(set) var empleados: [Empleado] = []
    @Published private(set) var isLoadingEmployees = false
    @Published private(set) var errorMessage: String?

    private let client: SupabaseClient

    init(client: SupabaseClient? = nil) {
        self.client = client ?? SupabaseClientFactory.shared
    }

    func loadEmployees() async {
        guard !isLoadingEmployees else { return }
        isLoadingEmployees = true
        errorMessage = nil
        defer { isLoadingEmployees = false }

        do {
            var result: [Empleado] = []
            var offset = 0
            while true {
                let page: [Empleado] = try await client
                    .from("perfiles")
                    .select("id,nombre_completo,rol")
                    .order("nombre_completo")
                    .range(from: offset, to: offset + 199)
                    .execute()
                    .value
                guard !Task.isCancelled else { return }
                result += page
                if page.count < 200 { break }
                offset += 200
            }
            empleados = result
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
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
        guard !isSaving else { throw AdminDataError.respuestaInvalida }
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

    func fetchAssignment(id: UUID) async throws -> Asignacion {
        try await client
            .from("asignaciones")
            .select(
                "id,tipo_flujo,titulo,ubicacion,nivel_prioridad,instrucciones,estado,fecha_creacion,fecha_limite," +
                "hitos_itinerario(*,hitos_colaboradores(*,perfiles(id,nombre_completo,rol))),asignacion_supervisores(usuario_id),asignacion_equipo(perfiles(id,nombre_completo,rol))"
            )
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    private func validate(_ draft: AsignacionDraft) throws {
        if let error = FormValidation.text(draft.titulo, field: "El título", minimum: 3, maximum: 120) {
            throw AdminDataError.campoInvalido(error)
        }
        if let instructions = draft.instruccionesOpcionales,
           let error = FormValidation.text(instructions, field: "Las instrucciones", minimum: 1, maximum: 2000, required: false) {
            throw AdminDataError.campoInvalido(error)
        }
        guard !draft.empleadosIDs.isEmpty else {
            throw AdminDataError.responsableRequerido
        }

        switch draft.tipoFlujo {
        case .operacionesCampo:
            guard let location = draft.ubicacion else {
                throw AdminDataError.ubicacionRequerida
            }
            if let error = FormValidation.text(location, field: "La ubicación", minimum: 3, maximum: 180) {
                throw AdminDataError.campoInvalido(error)
            }
            guard !draft.hitos.isEmpty else { throw AdminDataError.itinerarioRequerido }
            try validateMilestones(draft.hitos)
        case .tareaAdministrativa:
            guard draft.ubicacion == nil else {
                throw AdminDataError.tareaAdministrativaConItinerario
            }
            guard !draft.hitos.isEmpty else { throw AdminDataError.itinerarioRequerido }
            try validateMilestones(draft.hitos)
            guard draft.hitos.allSatisfy({
                $0.fechaProgramada >= draft.fechaCreacion
            }) else { throw AdminDataError.hitosFueraPeriodo }
        }
    }

    private func validateMilestones(_ milestones: [HitoDraft]) throws {
        let ordered = milestones.sorted { $0.orden < $1.orden }
        guard Set(ordered.map(\.orden)).count == ordered.count else {
            throw AdminDataError.secuenciaHitosInvalida
        }

        var previousDate: Date?
        for milestone in ordered {
            guard !milestone.colaboradoresIDs.isEmpty else { throw AdminDataError.responsableRequerido }
            if let error = FormValidation.text(milestone.titulo, field: "El título del hito", minimum: 2, maximum: 100) {
                throw AdminDataError.campoInvalido(error)
            }
            if let previousDate, milestone.fechaProgramada < previousDate {
                throw AdminDataError.secuenciaHitosInvalida
            }
            previousDate = milestone.fechaProgramada
        }
    }

    private func milestonePayloads(from drafts: [HitoDraft]) -> [MilestoneMutationPayload] {
        drafts.sorted { $0.orden < $1.orden }.map(MilestoneMutationPayload.init)
    }
}

private struct AssignmentMutationPayload: Encodable {
    let supervisores: [UUID]
    let tipoFlujo: TipoFlujo
    let titulo: String
    let ubicacion: String?
    let prioridad: PrioridadAsignacion
    let instrucciones: String?
    let fechaCreacion: Date
    let fechaLimite: Date?

    init(_ draft: AsignacionDraft) {
        supervisores = draft.supervisoresIDs
        tipoFlujo = draft.tipoFlujo
        titulo = draft.titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        ubicacion = draft.ubicacion
        prioridad = draft.prioridad
        instrucciones = draft.instruccionesOpcionales
        fechaCreacion = draft.fechaCreacion
        fechaLimite = draft.hitos.sorted { $0.orden < $1.orden }.last?.fechaProgramada
    }

    enum CodingKeys: String, CodingKey {
        case supervisores
        case tipoFlujo = "tipo_flujo"
        case titulo
        case ubicacion
        case prioridad = "nivel_prioridad"
        case instrucciones
        case fechaCreacion = "fecha_creacion"
        case fechaLimite = "fecha_limite"
    }
}

private struct MilestoneMutationPayload: Encodable {
    let colaboradores: [UUID]
    let id: UUID
    let orden: Int
    let titulo: String
    let horaEstimada: String
    let fechaProgramada: Date
    let estado: EstadoHito
    let notasIncidencias: String?

    init(_ draft: HitoDraft) {
        colaboradores = draft.colaboradoresIDs
        id = draft.id
        orden = draft.orden
        titulo = draft.titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        horaEstimada = draft.horaEstimada
        fechaProgramada = draft.fechaProgramada
        estado = draft.estado
        notasIncidencias = draft.notasIncidencias
    }

    enum CodingKeys: String, CodingKey {
        case colaboradores
        case id
        case orden
        case titulo = "descripcion"
        case horaEstimada = "hora_estimada"
        case fechaProgramada = "fecha_programada"
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
