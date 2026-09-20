import Foundation
import Combine

@MainActor
final class RegistrationViewModel: ObservableObject {
    @Published var busy = false
    @Published private(set) var registered = false
    @Published var username = ""
    @Published var fullName = ""
    @Published var email = ""
    @Published var phone = ""
    @Published var position = "Técnico de pantallas"
    @Published var password = ""
    @Published var confirmation = ""
    @Published var acceptedTerms = false
    @Published var notice: AuthNotice?
    let positions = ["Técnico de pantallas", "Técnico de sonido", "Técnico de iluminación", "Técnico de estructuras", "Administración", "Jefe de cuadrilla"]

    func legalNotice(_ title: String) {
        notice = AuthNotice(title: title, message: "El documento corporativo aún no está disponible. Solicítalo a administración antes de crear tu cuenta.")
    }

    func register(using auth: SessionViewModel) {
        let trimmed = [username, fullName, phone].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard trimmed.allSatisfy({ !$0.isEmpty }),
              AuthValidation.validEmail(email.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            notice = AuthNotice(title: "Revisa tus datos", message: "Completa todos los campos e introduce un correo válido.")
            return
        }
        guard phone.filter(\.isNumber).count >= 7 else {
            notice = AuthNotice(title: "Teléfono inválido", message: "Introduce un número de teléfono válido.")
            return
        }
        guard AuthValidation.passwordScore(password) == 4 else {
            notice = AuthNotice(title: "Revisa tu contraseña", message: "Usa al menos 8 caracteres, letras, números y un símbolo.")
            return
        }
        guard password == confirmation else {
            notice = AuthNotice(title: "Las contraseñas no coinciden", message: "Repite la misma contraseña en ambos campos.")
            return
        }
        guard acceptedTerms else {
            notice = AuthNotice(title: "Aceptación pendiente", message: "Debes leer y aceptar los términos y la política de privacidad.")
            return
        }
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await auth.signUp(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password,
                    username: trimmed[0], name: trimmed[1], phone: trimmed[2], job: position)
                password = ""
                confirmation = ""
                auth.notice = AuthNotice(title: "Cuenta creada: en revisión", message: "Tu cuenta está bajo revisión. La aprobación tarda aproximadamente 24 horas. Te avisaremos cuando un administrador apruebe tu acceso.")
                registered = true
            } catch { notice = .failure(error) }
        }
    }
}
