import Foundation
import Combine
import Supabase

@MainActor
final class AdminMessageViewModel: ObservableObject {
    @Published private(set) var mensajes: [Mensaje] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let client: SupabaseClient

    init(client: SupabaseClient? = nil) {
        self.client = client ?? SupabaseClientFactory.shared
    }

    func loadMessages() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result: [Mensaje] = try await client
                .from("comunicados")
                .select("id,asunto,mensaje,fecha_publicacion,leido_por")
                .order("fecha_publicacion", ascending: false)
                .execute()
                .value
            guard !Task.isCancelled else { return }
            mensajes = result
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func publishMessage(_ draft: MensajeDraft) async throws -> Mensaje {
        try validate(draft)
        return try await performMutation {
            let payload = MessageMutationPayload(
                asunto: draft.asunto.trimmingCharacters(in: .whitespacesAndNewlines),
                mensaje: draft.cuerpoMensaje.trimmingCharacters(in: .whitespacesAndNewlines),
                fechaPublicacion: .now,
                leidoPor: []
            )
            let created: Mensaje = try await client
                .from("comunicados")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            mensajes.insert(created, at: 0)
            return created
        }
    }

    @discardableResult
    func editMessage(id: UUID, draft: MensajeDraft) async throws -> Mensaje {
        try validate(draft)
        return try await performMutation {
            let payload = MessageUpdatePayload(
                asunto: draft.asunto.trimmingCharacters(in: .whitespacesAndNewlines),
                mensaje: draft.cuerpoMensaje.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let updated: Mensaje = try await client
                .from("comunicados")
                .update(payload)
                .eq("id", value: id)
                .select()
                .single()
                .execute()
                .value
            if let index = mensajes.firstIndex(where: { $0.id == id }) {
                mensajes[index] = updated
            }
            return updated
        }
    }

    func deleteMessage(id: UUID) async throws {
        guard !isLoading else { throw AdminDataError.respuestaInvalida }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let _: Mensaje = try await client
                .from("comunicados")
                .delete()
                .eq("id", value: id)
                .select()
                .single()
                .execute()
                .value
            mensajes.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func performMutation<T>(operation: () async throws -> T) async throws -> T {
        guard !isLoading else { throw AdminDataError.respuestaInvalida }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            return try await operation()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func validate(_ draft: MensajeDraft) throws {
        guard !draft.asunto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.cuerpoMensaje.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AdminDataError.mensajeInvalido
        }
    }
}

private struct MessageMutationPayload: Encodable {
    let asunto: String
    let mensaje: String
    let fechaPublicacion: Date
    let leidoPor: [UUID]

    enum CodingKeys: String, CodingKey {
        case asunto
        case mensaje
        case fechaPublicacion = "fecha_publicacion"
        case leidoPor = "leido_por"
    }
}

private struct MessageUpdatePayload: Encodable {
    let asunto: String
    let mensaje: String
}
