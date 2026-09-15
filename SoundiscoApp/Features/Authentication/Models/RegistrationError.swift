import Foundation

enum RegistrationError: LocalizedError {
    case sessionRequired
    var errorDescription: String? {
        "No se pudo iniciar la sesión tras el registro. Contacta con administración."
    }
}
