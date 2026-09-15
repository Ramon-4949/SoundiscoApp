import Foundation
import Combine
import Supabase

@MainActor
final class SessionViewModel: ObservableObject {
    private let client: SupabaseClient
    init(client: SupabaseClient? = nil) { self.client = client ?? SupabaseService.client }

    @Published private(set) var user: User?
    @Published private(set) var initializing = true
    @Published var recoveringPassword = false
    @Published var notice: AuthNotice?

    var userID: UUID? { user?.id }
    var userEmail: String? { user?.email }

    var displayName: String {
        user?.userMetadata["nombre_usuario"]?.stringValue
            ?? user?.userMetadata["nombre_completo"]?.stringValue
            ?? user?.email?.components(separatedBy: "@").first ?? "Equipo"
    }

    func observeSession() async {
        for await (event, session) in client.auth.authStateChanges {
            guard !Task.isCancelled else { return }
            if event == .passwordRecovery { recoveringPassword = true }
            if event == .signedOut { recoveringPassword = false }
            user = session?.user
            initializing = false
        }
    }

    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(email: email, password: password)
        user = session.user
    }

    func signUp(email: String, password: String, username: String, name: String, phone: String, job: String) async throws {
        let response = try await client.auth.signUp(
            email: email, password: password,
            data: ["nombre_usuario": .string(username), "nombre_completo": .string(name),
                   "telefono": .string(phone), "cargo": .string(job)]
        )
        guard let session = response.session else { throw RegistrationError.sessionRequired }
        user = session.user
    }

    func handle(_ url: URL) async {
        guard url.scheme == "soundisco", url.host == "auth", url.path == "/callback" else { return }
        do { _ = try await client.auth.session(from: url) }
        catch { notice = .failure(error) }
    }

    func signOut() async {
        do {
            try await client.auth.signOut(scope: .local)
            user = nil
            recoveringPassword = false
        } catch { notice = .failure(error) }
    }
}
