import Foundation

struct LoginAttemptStatus {
    let failures: Int
    let lockedUntil: Date?
}

final class LoginAttemptLimiter {
    let maximumAttempts: Int
    let lockDuration: TimeInterval
    private let defaults: UserDefaults

    init(maximumAttempts: Int = 5, lockDuration: TimeInterval = 15 * 60, defaults: UserDefaults = .standard) {
        self.maximumAttempts = maximumAttempts
        self.lockDuration = lockDuration
        self.defaults = defaults
    }

    func status(for email: String, now: Date = .now) -> LoginAttemptStatus {
        let key = identifier(email)
        guard !key.isEmpty else { return LoginAttemptStatus(failures: 0, lockedUntil: nil) }
        let lockedUntil = defaults.object(forKey: "login.lockedUntil.\(key)") as? Date
        if let lockedUntil, lockedUntil > now {
            return LoginAttemptStatus(failures: maximumAttempts, lockedUntil: lockedUntil)
        }
        if lockedUntil != nil { reset(email: email) }
        return LoginAttemptStatus(failures: defaults.integer(forKey: "login.failures.\(key)"), lockedUntil: nil)
    }

    @discardableResult
    func recordFailure(for email: String, now: Date = .now) -> LoginAttemptStatus {
        let key = identifier(email)
        guard !key.isEmpty else { return LoginAttemptStatus(failures: 0, lockedUntil: nil) }
        let current = status(for: email, now: now).failures + 1
        defaults.set(current, forKey: "login.failures.\(key)")
        guard current >= maximumAttempts else { return LoginAttemptStatus(failures: current, lockedUntil: nil) }
        let until = now.addingTimeInterval(lockDuration)
        defaults.set(until, forKey: "login.lockedUntil.\(key)")
        return LoginAttemptStatus(failures: current, lockedUntil: until)
    }

    func reset(email: String) {
        let key = identifier(email)
        defaults.removeObject(forKey: "login.failures.\(key)")
        defaults.removeObject(forKey: "login.lockedUntil.\(key)")
    }

    private func identifier(_ email: String) -> String {
        Data(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
    }
}
