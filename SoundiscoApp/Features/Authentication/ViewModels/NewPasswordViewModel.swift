import Foundation
import Combine
import Supabase

@MainActor
final class NewPasswordViewModel: ObservableObject {
    @Published var password = ""
    @Published var confirmation = ""
    @Published var currentPassword = ""
    let requiresCurrentPassword: Bool
    @Published private(set) var busy = false
    @Published private(set) var completed = false
    @Published var notice: AuthNotice?
    @Published private(set) var validationAttempted = false
    private let client: SupabaseClient
    init(client: SupabaseClient? = nil, requiresCurrentPassword: Bool = false) {
        self.client = client ?? SupabaseService.client
        self.requiresCurrentPassword = requiresCurrentPassword
    }

    var currentPasswordError: String? {
        validationAttempted && requiresCurrentPassword && currentPassword.isEmpty ? "Introduce tu contraseña actual." : nil
    }

    var passwordError: String? { validationAttempted ? FormValidation.password(password) : nil }
    var confirmationError: String? {
        validationAttempted ? FormValidation.confirmation(confirmation, password: password) : nil
    }

    func save() async -> Bool {
        guard !busy, !completed else { return false }
        validationAttempted = true
        if let message = currentPasswordError ?? FormValidation.password(password)
            ?? FormValidation.confirmation(confirmation, password: password) {
            notice = AuthNotice(title: "Revisa los campos", message: message)
            return false
        }
        busy = true
        defer { busy = false }
        do {
            if requiresCurrentPassword {
                guard password != currentPassword else {
                    notice = AuthNotice(title: "Elige otra contraseña", message: "La nueva contraseña debe ser diferente de la actual.")
                    return false
                }
                let original = try await client.auth.session.user
                guard let email = original.email else {
                    notice = AuthNotice(title: "Correo no disponible", message: "Vuelve a iniciar sesión con tu correo.")
                    return false
                }
                let verification = TemporaryAuth.client()
                do {
                    let session = try await verification.auth.signIn(email: email, password: currentPassword)
                    guard session.user.id == original.id,
                          try await client.auth.session.user.id == original.id else {
                        try? await verification.auth.signOut(scope: .local)
                        notice = AuthNotice(title: "La sesión cambió", message: "Vuelve a abrir el formulario e inténtalo de nuevo.")
                        return false
                    }
                    try await verification.auth.update(user: UserAttributes(password: password))
                    try? await verification.auth.signOut(scope: .local)
                } catch {
                    try? await verification.auth.signOut(scope: .local)
                    throw error
                }
            } else {
                try await client.auth.update(user: UserAttributes(password: password))
            }
            completed = true
            validationAttempted = false
            currentPassword = ""
            password = ""
            confirmation = ""
            return true
        } catch { notice = .failure(error); return false }
    }
}
