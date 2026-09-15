import Foundation

enum AuthValidation {
    static func validEmail(_ value: String) -> Bool {
        value.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
    static func passwordScore(_ value: String) -> Int {
        guard !value.isEmpty else { return 0 }
        return [value.count >= 8, value.rangeOfCharacter(from: .letters) != nil,
                value.rangeOfCharacter(from: .decimalDigits) != nil,
                value.rangeOfCharacter(from: .punctuationCharacters.union(.symbols)) != nil]
            .filter { $0 }.count
    }
}
