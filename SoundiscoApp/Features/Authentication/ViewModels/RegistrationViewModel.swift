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
    @Published var position = "Técnico de sonido"
    @Published var password = ""
    @Published var confirmation = ""
    @Published var acceptedTerms = false
    @Published var notice: AuthNotice?
    @Published private(set) var validationAttempted = false
    let positions = [
        "Técnico de sonido",
        "Técnico audiovisuales",
        "Técnico de iluminación",
        "Encargado de estructura",
        "Encargado de almacén",
        "Supervisor",
        "Administrativo",
        "Contabilidad",
        "Recursos Humanos",
        "Marketing Digital",
        "Chofer/Técnico de sonido",
        "Chofer/Técnico de audiovisuales",
        "Chofer/Técnico de iluminación",
        "Chofer/Encargado de estructura",
        "Chofer/Encargado de almacén"
    ]

    var usernameError: String? { visible(FormValidation.username(username)) }
    var fullNameError: String? { visible(FormValidation.fullName(fullName)) }
    var emailError: String? { visible(FormValidation.email(email)) }
    var phoneError: String? { visible(FormValidation.phone(phone)) }
    var passwordError: String? {
        visible(FormValidation.password(password, personalValues: [username, fullName, email.components(separatedBy: "@").first ?? ""]))
    }
    var confirmationError: String? { visible(FormValidation.confirmation(confirmation, password: password)) }
    var positionError: String? { visible(positions.contains(position) ? nil : "Selecciona un cargo válido.") }
    var termsError: String? { visible(acceptedTerms ? nil : "Debes aceptar los términos y la política de privacidad.") }

    private var formIsValid: Bool {
        FormValidation.username(username) == nil && FormValidation.fullName(fullName) == nil &&
        FormValidation.email(email) == nil && FormValidation.phone(phone) == nil &&
        FormValidation.password(password, personalValues: [username, fullName, email.components(separatedBy: "@").first ?? ""]) == nil &&
        FormValidation.confirmation(confirmation, password: password) == nil &&
        positions.contains(position) && acceptedTerms
    }

    private func visible(_ error: String?) -> String? { validationAttempted ? error : nil }

    func legalNotice(_ title: String) {
        notice = AuthNotice(title: title, message: "El documento corporativo aún no está disponible. Solicítalo a administración antes de crear tu cuenta.")
    }

    func register(using auth: SessionViewModel) {
        validationAttempted = true
        guard formIsValid else { return }
        let trimmed = [username, fullName, phone].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
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
