import Foundation

enum AuthValidation {
    static func validEmail(_ value: String) -> Bool {
        FormValidation.email(value) == nil
    }
    static func passwordScore(_ value: String) -> Int {
        guard !value.isEmpty else { return 0 }
        return [value.count >= 8,
                value.rangeOfCharacter(from: .lowercaseLetters) != nil && value.rangeOfCharacter(from: .uppercaseLetters) != nil,
                value.rangeOfCharacter(from: .decimalDigits) != nil,
                value.rangeOfCharacter(from: .punctuationCharacters.union(.symbols)) != nil]
            .filter { $0 }.count
    }
}
