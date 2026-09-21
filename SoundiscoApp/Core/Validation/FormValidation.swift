import Foundation
import SwiftUI

enum FormValidation {
    static func username(_ value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return "El nombre de usuario es obligatorio." }
        if !(3...30).contains(clean.count) { return "Debe tener entre 3 y 30 caracteres." }
        if clean.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) == nil {
            return "Usa letras, números, punto, guion o guion bajo; debe comenzar con una letra o número."
        }
        return nil
    }

    static func fullName(_ value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return "El nombre completo es obligatorio." }
        if !(2...80).contains(clean.count) { return "Debe tener entre 2 y 80 caracteres." }
        let allowed = CharacterSet.letters
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "'-’"))
        if clean.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Usa solamente letras, espacios, apóstrofes o guiones."
        }
        return nil
    }

    static func email(_ value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return "El correo electrónico es obligatorio." }
        if clean.count > 254 { return "El correo es demasiado largo." }
        if clean.contains("..") || clean.range(
            of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,63}$"#,
            options: [.regularExpression, .caseInsensitive]
        ) == nil { return "Introduce un correo válido, por ejemplo nombre@empresa.com." }
        return nil
    }

    static func phone(_ value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return "El número de teléfono es obligatorio." }
        let permitted = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "+() -"))
        if clean.unicodeScalars.contains(where: { !permitted.contains($0) }) {
            return "El teléfono solo admite números, espacios, +, paréntesis y guiones."
        }
        let digits = clean.filter(\.isNumber)
        if !(10...15).contains(digits.count) { return "Introduce un teléfono de 10 a 15 dígitos." }
        return nil
    }

    static func password(_ value: String, personalValues: [String] = []) -> String? {
        if value.isEmpty { return "La contraseña es obligatoria." }
        if !(8...72).contains(value.count) { return "Debe tener entre 8 y 72 caracteres." }
        if value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { return "No puede contener espacios." }
        if value.rangeOfCharacter(from: .lowercaseLetters) == nil { return "Añade al menos una letra minúscula." }
        if value.rangeOfCharacter(from: .uppercaseLetters) == nil { return "Añade al menos una letra mayúscula." }
        if value.rangeOfCharacter(from: .decimalDigits) == nil { return "Añade al menos un número." }
        if value.rangeOfCharacter(from: .punctuationCharacters.union(.symbols)) == nil {
            return "Añade al menos un carácter especial, por ejemplo !, @ o #."
        }
        let lower = value.lowercased()
        if personalValues.lazy.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
            .filter({ $0.count >= 3 }).contains(where: lower.contains) {
            return "No incluyas tu nombre, usuario o correo en la contraseña."
        }
        return nil
    }

    static func confirmation(_ value: String, password: String) -> String? {
        if value.isEmpty { return "Confirma la contraseña." }
        return value == password ? nil : "Las contraseñas no coinciden."
    }

    static func text(_ value: String, field: String, minimum: Int, maximum: Int, required: Bool = true) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return required ? "\(field) es obligatorio." : nil }
        if clean.count < minimum { return "Debe tener al menos \(minimum) caracteres." }
        if clean.count > maximum { return "No puede superar \(maximum) caracteres." }
        if clean.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) && ![9, 10, 13].contains($0.value)
        }) {
            return "Contiene caracteres no permitidos."
        }
        return nil
    }
}

struct FieldValidationMessage: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Error: \(message)")
        }
    }
}

private struct ValidationBorder: ViewModifier {
    let message: String?

    func body(content: Content) -> some View {
        content.overlay {
            if message != nil {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.red, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityHint(message ?? "")
    }
}

extension View {
    func validationBorder(_ message: String?) -> some View {
        modifier(ValidationBorder(message: message))
    }
}
