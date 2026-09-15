import Foundation
import Combine

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var busy = false
    @Published var notice: AuthNotice?
    @Published var rememberEmail: Bool {
        didSet {
            defaults.set(rememberEmail, forKey: "rememberEmail")
            if !rememberEmail { defaults.removeObject(forKey: "rememberedEmail") }
        }
    }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rememberEmail = defaults.bool(forKey: "rememberEmail")
        if rememberEmail { email = defaults.string(forKey: "rememberedEmail") ?? "" }
    }
    func signIn(using auth: SessionViewModel) {
        email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AuthValidation.validEmail(email), !password.isEmpty else {
            notice = AuthNotice(title: "Revisa tus datos", message: "Introduce un correo válido y tu contraseña.")
            return
        }
        defaults.set(rememberEmail ? email : "", forKey: "rememberedEmail")
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await auth.signIn(email: email, password: password) }
            catch { notice = .failure(error) }
        }
    }
}
