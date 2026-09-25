import Foundation
import Combine
import Supabase
import LocalAuthentication

@MainActor
final class SessionViewModel: ObservableObject {
    private let client: SupabaseClient
    init(client: SupabaseClient? = nil) { self.client = client ?? SupabaseService.client }

    @Published private(set) var user: User?
    @Published private(set) var initializing = true
    @Published var recoveringPassword = false
    @Published var notice: AuthNotice?
    @Published private(set) var biometricEnabled = false
    @Published private(set) var isLocked = false
    @Published private(set) var biometricBusy = false
    @Published private(set) var signingOut = false
    @Published private(set) var biometricLoginBusy = false
    private var biometricContext: LAContext?
    private var biometricRevision = 0

    var jobTitle: String? { user?.userMetadata["cargo"]?.stringValue }

    func setBiometricEnabled(_ enabled: Bool) async {
        guard let id = userID, !biometricBusy else { return }
        if enabled {
            guard await authenticateBiometrically(), userID == id else { return }
        }
        biometricEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "biometric.\(id.uuidString)")
        if !enabled { isLocked = false }
    }

    func lockSession() {
        biometricRevision += 1
        biometricContext?.invalidate()
        if userID != nil && biometricEnabled { isLocked = true }
    }

    func unlockSession() async {
        await signInWithBiometrics()
    }

    func signInWithBiometrics() async {
        guard !biometricLoginBusy, !biometricBusy, !signingOut else { return }
        guard let id = userID else {
            notice = AuthNotice(title: "Activa Face ID", message: "Inicia sesión con tu correo y contraseña y activa Face ID en Mi perfil. Después podrás entrar con biometría mientras conserves tu sesión en este dispositivo.")
            return
        }
        guard biometricEnabled else {
            notice = AuthNotice(title: "Face ID desactivado", message: "Activa Face ID / Biometría en Mi perfil para utilizar este acceso.")
            return
        }
        biometricLoginBusy = true
        defer { biometricLoginBusy = false }
        let revision = biometricRevision
        guard await authenticateBiometrically(), userID == id else { return }
        do {
            let session = try await client.auth.session
            guard session.user.id == id, userID == id, revision == biometricRevision else { return }
            isLocked = false
        } catch {
            notice = AuthNotice(title: "No se pudo recuperar la sesión", message: "Comprueba tu conexión o vuelve a entrar con correo y contraseña.")
        }
    }

    private func authenticateBiometrically() async -> Bool {
        guard !biometricBusy else { return false }
        biometricBusy = true
        defer { biometricBusy = false; biometricContext = nil }
        let context = LAContext()
        biometricContext = context
        context.localizedCancelTitle = "Cancelar"
        context.localizedFallbackTitle = ""
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            notice = AuthNotice(title: "Biometría no disponible", message: "Configura Face ID o Touch ID en los ajustes del dispositivo. Puedes acceder con tu correo y contraseña.")
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Confirma tu identidad para acceder a SounDisco.")
        } catch {
            let code = (error as NSError).code
            if code != LAError.userCancel.rawValue && code != LAError.systemCancel.rawValue && code != LAError.appCancel.rawValue {
                notice = AuthNotice(title: "No se pudo verificar tu identidad", message: error.localizedDescription)
            }
            return false
        }
    }

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
            let previousID = userID
            user = session?.user
            if initializing || previousID != userID {
                biometricEnabled = userID.map { UserDefaults.standard.bool(forKey: "biometric.\($0.uuidString)") } ?? false
                isLocked = false
            }
            initializing = false
        }
    }

    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(email: email, password: password)
        user = session.user
        isLocked = false
        biometricEnabled = UserDefaults.standard.bool(forKey: "biometric.\(session.user.id.uuidString)")
    }

    func refreshProfileIdentity() async {
        do { user = try await client.auth.user() }
        catch { notice = .failure(error) }
    }

    func signUp(email: String, password: String, username: String, name: String, phone: String, job: String) async throws {
        let response = try await client.auth.signUp(
            email: email, password: password,
            data: ["nombre_usuario": .string(username), "nombre_completo": .string(name),
                   "telefono": .string(phone), "cargo": .string(job)]
        )
        // Auth can create the account without issuing a session while email confirmation is enabled.
        if let session = response.session { user = session.user }
    }

    func deleteAccount() async throws {
        guard !signingOut else { return }
        signingOut = true
        defer { signingOut = false }
        try await client.rpc("delete_my_account").execute()
        if let id = userID { UserDefaults.standard.removeObject(forKey: "biometric.\(id.uuidString)") }
        biometricRevision += 1
        biometricContext?.invalidate()
        await PushNotificationService.shared.clearLocalRegistration()
        try? await client.auth.signOut(scope: .local)
        user = nil
        biometricEnabled = false
        isLocked = false
        recoveringPassword = false
        notice = AuthNotice(title: "Cuenta eliminada", message: "Tu cuenta y tus datos de perfil se han eliminado.")
    }

    func handle(_ url: URL) async {
        guard url.scheme == "soundisco", url.host == "auth", url.path == "/callback" else { return }
        do { _ = try await client.auth.session(from: url) }
        catch { notice = .failure(error) }
    }

    func signOut() async {
        guard !signingOut else { return }
        signingOut = true
        defer { signingOut = false }
        biometricRevision += 1
        biometricContext?.invalidate()

        await performRemoteSignOut()
    }

    func usePasswordInstead() async {
        guard !signingOut else { return }
        signingOut = true
        defer { signingOut = false }
        biometricRevision += 1
        biometricContext?.invalidate()

        if let id = userID {
            UserDefaults.standard.set(false, forKey: "biometric.\(id.uuidString)")
        }
        biometricEnabled = false
        await performRemoteSignOut()
    }

    private func performRemoteSignOut() async {
        do {
            try await PushNotificationService.shared.disconnect()
            try await client.auth.signOut(scope: .local)
            user = nil
            recoveringPassword = false
            isLocked = false
            biometricEnabled = false
        } catch { notice = .failure(error) }
    }
}
