import Foundation
import Combine
import Supabase

enum NotificationFilter: String, CaseIterable, Identifiable {
    case all = "Todas", unread = "Sin leer", assignments = "Asignaciones", bulletins = "Comunicados"
    var id: String { rawValue }
}

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published private(set) var items: [EmployeeNotification] = []
    @Published private(set) var loading = true
    @Published var failure: String?
    @Published var filter: NotificationFilter = .all

    private let client: SupabaseClient
    private var owner: UUID?
    private var generation = UUID()
    init(client: SupabaseClient? = nil) { self.client = client ?? SupabaseService.client }
    var unreadCount: Int { items.filter(\.unread).count }
    var filtered: [EmployeeNotification] {
        items.filter {
            switch filter {
            case .all: true
            case .unread: $0.unread
            case .assignments: $0.destino_tipo == "asignacion"
            case .bulletins: $0.destino_tipo == "comunicado"
            }
        }
    }

    func observe(userID: UUID) async {
        let run = UUID()
        generation = run
        owner = userID
        items = []
        loading = true
        let channel = client.channel("notifications-\(userID)-\(run)")
        let changes = channel.postgresChange(AnyAction.self, schema: "public",
            table: "notificaciones_app", filter: .eq("perfil_id", value: userID.uuidString))
        await load(userID: userID)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                do {
                    try await channel.subscribeWithError()
                    for await _ in changes {
                        guard !Task.isCancelled else { break }
                        await self?.load(userID: userID)
                    }
                } catch { /* Periodic reconciliation handles reconnect failures. */ }
            }
            group.addTask { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { break }
                    await self?.load(userID: userID)
                }
            }
            await group.waitForAll()
        }
        await client.removeChannel(channel)
        if generation == run { owner = nil; items = [] }
    }

    func load(userID: UUID) async {
        let run = generation
        do {
            var result: [EmployeeNotification] = []
            var offset = 0
            while true {
                let page: [EmployeeNotification] = try await client.from("notificaciones_app")
                    .select().eq("perfil_id", value: userID).order("fecha_creacion", ascending: false).order("id")
                    .range(from: offset, to: offset + 199).execute().value
                guard !Task.isCancelled, generation == run, owner == userID else { return }
                result += page
                if page.count < 200 { break }
                offset += 200
            }
            items = result
            failure = nil
        } catch { if !Task.isCancelled, generation == run { failure = AuthNotice.failure(error).message } }
        if generation == run { loading = false }
    }

    func markRead(_ id: UUID? = nil) async {
        guard let owner else { return }
        struct Params: Encodable { let p_id: UUID? }
        do {
            try await client.rpc("notifications_mark_read", params: Params(p_id: id)).execute()
            guard self.owner == owner else { return }
            for index in items.indices where id == nil || items[index].id == id { items[index].leida = true }
        } catch { failure = AuthNotice.failure(error).message }
    }
}
