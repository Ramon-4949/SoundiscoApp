import Foundation
import Combine
import Supabase

@MainActor
final class BulletinsViewModel: ObservableObject {
    @Published private(set) var items: [Bulletin] = []
    @Published private(set) var loading = true
    @Published private(set) var failure: String?

    private let client: SupabaseClient
    private var isRequestActive = false
    init(client: SupabaseClient? = nil) { self.client = client ?? SupabaseService.client }
    func load() async {
        guard !isRequestActive else { return }
        isRequestActive = true
        loading = true
        failure = nil
        defer { loading = false; isRequestActive = false }
        do {
            var result: [Bulletin] = []
            var offset = 0
            while true {
                let page: [Bulletin] = try await client.from("comunicados").select()
                    .order("fecha_publicacion", ascending: false).order("id")
                    .range(from: offset, to: offset + 199).execute().value
                guard !Task.isCancelled else { return }
                result += page
                if page.count < 200 { break }
                offset += 200
            }
            items = result
        } catch { if !Task.isCancelled { failure = AuthNotice.failure(error).message } }
    }
}
