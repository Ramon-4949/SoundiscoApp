import Foundation
import Combine
import Supabase

@MainActor
final class AdminUsersViewModel: ObservableObject {
    @Published private(set) var users: [ManagedAccount] = []
    @Published private(set) var loading = false
    @Published private(set) var savingID: UUID?
    @Published var error: String?
    @Published var search = ""
    @Published var filter: AccountAccessState = .pendiente
    private let client: SupabaseClient
    init(client: SupabaseClient? = nil) { self.client = client ?? SupabaseService.client }

    var pendingCount: Int { users.filter { $0.estado == .pendiente }.count }
    var filtered: [ManagedAccount] {
        users.filter {
            $0.estado == filter && (search.isEmpty || "\($0.displayName) \($0.email ?? "") \($0.cargo ?? "")".localizedStandardContains(search))
        }
    }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            var result: [ManagedAccount] = []
            while true {
                let page: [ManagedAccount] = try await client.rpc("admin_list_accounts", params: ["p_offset": result.count]).execute().value
                guard !Task.isCancelled else { return }
                result += page
                if page.count < 200 { break }
            }
            users = result
            error = nil
        } catch { if !Task.isCancelled { self.error = AuthNotice.failure(error).message } }
    }

    func decide(_ user: ManagedAccount, approved: Bool) async {
        guard savingID == nil else { return }
        savingID = user.id
        defer { savingID = nil }
        do {
            try await client.rpc("admin_review_account", params: [
                "p_user_id": user.id.uuidString,
                "p_estado": approved ? "aprobada" : "rechazada"
            ]).execute()
            await load()
        } catch { self.error = AuthNotice.failure(error).message }
    }
}
