import Foundation
import Combine
import Supabase

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var busy = false
    @Published var notice: AuthNotice?
    @Published private(set) var failedAttempts = 0
    @Published private(set) var lockedUntil: Date?
    @Published private(set) var validationAttempted = false
    @Published var rememberEmail: Bool {
        didSet {
            defaults.set(rememberEmail, forKey: "rememberEmail")
            if !rememberEmail { defaults.removeObject(forKey: "rememberedEmail") }
        }
    }
    private let defaults: UserDefaults
    private let limiter: LoginAttemptLimiter

    init(defaults: UserDefaults = .standard, limiter: LoginAttemptLimiter? = nil) {
        self.defaults = defaults
        self.limiter = limiter ?? LoginAttemptLimiter(defaults: defaults)
        rememberEmail = defaults.bool(forKey: "rememberEmail")
        if rememberEmail { email = defaults.string(forKey: "rememberedEmail") ?? "" }
        refreshAttemptStatus()
    }

    var emailError: String? { validationAttempted ? FormValidation.email(email) : nil }
    var passwordError: String? {
        guard validationAttempted else { return nil }
        return password.isEmpty ? "La contraseña es obligatoria." : nil
    }

    func isLocked(at date: Date = .now) -> Bool { lockedUntil.map { $0 > date } ?? false }

    func attemptMessage(at date: Date = .now) -> String? {
        if let lockedUntil, lockedUntil > date {
            let seconds = max(1, Int(lockedUntil.timeIntervalSince(date).rounded(.up)))
            return "Demasiados intentos. Inténtalo nuevamente en \(seconds / 60):\(String(format: "%02d", seconds % 60))."
        }
        guard failedAttempts > 0 else { return nil }
        return "Quedan \(max(0, limiter.maximumAttempts - failedAttempts)) intentos antes del bloqueo temporal."
    }

    func refreshAttemptStatus(now: Date = .now) {
        let status = limiter.status(for: email, now: now)
        failedAttempts = status.failures
        lockedUntil = status.lockedUntil
    }

    func signIn(using auth: SessionViewModel) {
        email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        validationAttempted = true
        refreshAttemptStatus()
        guard emailError == nil, passwordError == nil, !isLocked() else { return }
        defaults.set(rememberEmail ? email : "", forKey: "rememberedEmail")
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await auth.signIn(email: email, password: password)
                limiter.reset(email: email)
                failedAttempts = 0
                lockedUntil = nil
            } catch {
                if Self.isCredentialFailure(error) {
                    let status = limiter.recordFailure(for: email)
                    failedAttempts = status.failures
                    lockedUntil = status.lockedUntil
                    let detail = attemptMessage() ?? "Revisa el correo y la contraseña."
                    notice = AuthNotice(title: status.lockedUntil == nil ? "Credenciales incorrectas" : "Acceso bloqueado temporalmente", message: detail)
                } else {
                    notice = .failure(error)
                }
            }
        }
    }

    private static func isCredentialFailure(_ error: Error) -> Bool {
        if let authError = error as? AuthError,
           case .api(_, let errorCode, _, _) = authError,
           errorCode == .invalidCredentials {
            return true
        }
        let message = error.localizedDescription.lowercased()
        return message.contains("invalid login credentials") ||
            (message.contains("credencial") && (message.contains("inválid") || message.contains("incorrect")))
    }
}
