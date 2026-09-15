import Foundation
import Combine
import Supabase

@MainActor
final class NewPasswordViewModel: ObservableObject {
    @Published var password = ""
    @Published var confirmation = ""
    @Published private(set) var busy = false
    @Published var notice: AuthNotice?
    private let client: SupabaseClient
    init(client: SupabaseClient? = nil) { self.client = client ?? SupabaseService.client }

    func save() async -> Bool {
        guard !busy else { return false }
        guard AuthValidation.passwordScore(password) == 4, password == confirmation else {
            notice = AuthNotice(title: "Revisa la contraseña", message: "Cumple los requisitos y escribe la misma contraseña en ambos campos.")
            return false
        }
        busy = true
        defer { busy = false }
        do {
            try await client.auth.update(user: UserAttributes(password: password))
            password = ""
            confirmation = ""
            return true
        } catch { notice = .failure(error); return false }
    }
}
