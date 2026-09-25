import Foundation
import Combine
import Supabase

nonisolated final class TemporaryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func remove(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}

@MainActor
enum TemporaryAuth {
    static func client() -> SupabaseClient {
        SupabaseClient(supabaseURL: SupabaseConfiguration.projectURL,
                       supabaseKey: SupabaseConfiguration.publishableKey,
                       options: .init(auth: .init(storage: TemporaryAuthStorage(), autoRefreshToken: false)))
    }
}

@MainActor
final class PasswordRecoveryViewModel: ObservableObject {
    enum Step { case email, code, password, complete }
    @Published var email: String
    @Published var code = ""
    @Published private(set) var step: Step = .email
    @Published private(set) var busy = false
    @Published var notice: AuthNotice?
    @Published private(set) var validationAttempted = false
    @Published private(set) var resendAt = Date.distantPast
    @Published private(set) var sentEmail = ""
    let client: SupabaseClient

    init(email: String, client: SupabaseClient? = nil) {
        self.email = email
        self.client = client ?? TemporaryAuth.client()
    }

    var emailError: String? { validationAttempted ? FormValidation.email(email) : nil }

    func send() async {
        guard !busy else { return }
        guard Date.now >= resendAt else {
            notice = AuthNotice(title: "Espera antes de reenviar", message: "Podrás solicitar otro código cuando termine la cuenta regresiva.")
            return
        }
        validationAttempted = true
        let address = step == .email ? email.trimmingCharacters(in: .whitespacesAndNewlines) : sentEmail
        guard FormValidation.email(address) == nil else { return }
        busy = true
        defer { busy = false }
        do {
            try await client.auth.resetPasswordForEmail(address)
            sentEmail = address
            code = ""
            resendAt = .now.addingTimeInterval(60)
            step = .code
        } catch { notice = .failure(error) }
    }

    func verify() async {
        guard !busy else { return }
        guard (6...10).contains(code.count), code.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            notice = AuthNotice(title: "Código incompleto", message: "Introduce el código que recibiste por correo.")
            return
        }
        busy = true
        defer { busy = false }
        do {
            _ = try await client.auth.verifyOTP(email: sentEmail, token: code, type: .recovery)
            _ = try await client.auth.session
            code = ""
            step = .password
        } catch { notice = .failure(error) }
    }

    func finish() async {
        try? await client.auth.signOut(scope: .local)
        LoginAttemptLimiter().reset(email: sentEmail)
        step = .complete
    }

    func cancel() async {
        try? await client.auth.signOut(scope: .local)
    }
}
