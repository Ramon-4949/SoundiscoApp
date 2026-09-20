import Foundation
import Combine
import Supabase

@MainActor
final class AccountAccessViewModel: ObservableObject {
    @Published private(set) var state: AccountAccessState?
    @Published private(set) var failure: String?
    private let client: SupabaseClient
    init(client: SupabaseClient? = nil) { self.client = client ?? SupabaseService.client }

    func refresh() async {
        do {
            let access: AccountAccess = try await client.rpc("my_account_access").execute().value
            guard !Task.isCancelled else { return }
            state = access.estado
            failure = nil
        } catch {
            guard !Task.isCancelled else { return }
            state = nil
            failure = AuthNotice.failure(error).message
        }
    }
}
