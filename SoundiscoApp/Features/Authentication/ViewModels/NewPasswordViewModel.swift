import Foundation
import Combine
import Supabase

@MainActor
final class NewPasswordViewModel: ObservableObject {
    @Published var password = ""
    @Published var confirmation = ""
    @Published private(set) var busy = false
    @Published var notice: AuthNotice?
    @Published private(set) var validationAttempted = false
    private let client: SupabaseClient
    init(client: SupabaseClient? = nil) { self.client = client ?? SupabaseService.client }

    var passwordError: String? { validationAttempted ? FormValidation.password(password) : nil }
    var confirmationError: String? {
        validationAttempted ? FormValidation.confirmation(confirmation, password: password) : nil
    }

    func save() async -> Bool {
        guard !busy else { return false }
        validationAttempted = true
        guard FormValidation.password(password) == nil,
              FormValidation.confirmation(confirmation, password: password) == nil else { return false }
        busy = true
        defer { busy = false }
        do {
            try await client.auth.update(user: UserAttributes(password: password))
            password = ""
            confirmation = ""
            return true
        } catch { notice = .failure(error); return false }
    }
}
