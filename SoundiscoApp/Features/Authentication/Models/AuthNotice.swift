import Foundation

struct AuthNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    static let unavailable = AuthNotice(title: "Servicio no disponible", message: "El acceso corporativo todavía no está habilitado. Contacta con administración.")
}

extension AuthNotice {
    static func failure(_ error: Error) -> AuthNotice {
        let raw = error.localizedDescription
        let text: String
        if raw.localizedCaseInsensitiveContains("Invalid login credentials") {
            text = "El correo o la contraseña no son correctos."
        } else if raw.localizedCaseInsensitiveContains("Email not confirmed") {
            text = "La cuenta todavía no está habilitada. Contacta con administración."
        } else if raw.localizedCaseInsensitiveContains("rate limit") {
            text = "Has realizado varios intentos. Espera unos minutos y vuelve a intentarlo."
        } else if error is URLError {
            text = "No se pudo conectar. Revisa tu conexión a internet e inténtalo de nuevo."
        } else { text = raw }
        return AuthNotice(title: "No se pudo completar", message: text)
    }
}
