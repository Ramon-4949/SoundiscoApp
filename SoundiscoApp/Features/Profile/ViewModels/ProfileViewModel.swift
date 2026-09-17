import Foundation
import Combine
import Supabase

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var profile: EmployeeProfile?
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    private let client: SupabaseClient
    init(client: SupabaseClient? = nil) { self.client = client ?? SupabaseService.client }
    func load(userID: UUID) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            let profiles: [EmployeeProfile] = try await client.from("perfiles")
                .select().eq("id", value: userID).limit(1).execute().value
            guard !Task.isCancelled else { return }
            profile = profiles.first
            if profile == nil { error = "Tu cuenta está activa, pero falta su perfil de empleado. Contacta con administración." }
        } catch {
            guard !Task.isCancelled else { return }
            self.error = AuthNotice.failure(error).message
        }

    }
}
