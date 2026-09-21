import Foundation
import Combine
import Supabase

@MainActor
final class PasswordRecoveryViewModel: ObservableObject {
    @Published var email: String
    @Published private(set) var busy = false
    @Published var notice: AuthNotice?
    @Published private(set) var validationAttempted = false
    private let client: SupabaseClient

    init(email: String, client: SupabaseClient? = nil) {
        self.email = email
        self.client = client ?? SupabaseService.client
    }

    var emailError: String? { validationAttempted ? FormValidation.email(email) : nil }

    func send() async {
        guard !busy else { return }
        validationAttempted = true
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FormValidation.email(cleanEmail) == nil else { return }
        busy = true
        defer { busy = false }
        do {
            try await client.auth.resetPasswordForEmail(cleanEmail, redirectTo: SupabaseService.callback)
            notice = AuthNotice(title: "Revisa tu correo", message: "Si existe una cuenta con este correo, recibirás un enlace para cambiar tu contraseña.")
        } catch { notice = .failure(error) }
    }
}
