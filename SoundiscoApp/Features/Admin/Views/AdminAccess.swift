import SwiftUI

private struct AdminAccessKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isAdministrator: Bool {
        get { self[AdminAccessKey.self] }
        set { self[AdminAccessKey.self] = newValue }
    }
}
