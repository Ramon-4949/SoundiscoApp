import Foundation
import Combine
import Supabase
import UserNotifications

enum NotificationFilter: String, CaseIterable, Identifiable {
    case all = "Todas", unread = "Sin leer", assignments = "Asignaciones", bulletins = "Comunicados"
    var id: String { rawValue }
}

struct NotificationRow: Identifiable {
    let notification: EmployeeNotification
    let timeLabel: String
    var id: UUID { notification.id }
}

struct NotificationDaySection: Identifiable {
    let day: Date
    let title: String
    let rows: [NotificationRow]
    var id: Date { day }
}

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published private(set) var items: [EmployeeNotification] = []
    @Published private(set) var sections: [NotificationDaySection] = []
    @Published private(set) var loading = true
    @Published private(set) var loadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var unreadCount = 0
    @Published private(set) var unreadBulletinIDs: Set<UUID> = []
    @Published private(set) var unreadMessageCount = 0
    @Published private(set) var filter: NotificationFilter = .all
    @Published var failure: String?

    private struct BulletinUnread: Decodable {
        let destino_id: UUID?
        let tipo: String?
    }

    private struct NotificationID: Decodable {
        let id: UUID
    }

    private let pageSize = 50
    private let client: SupabaseClient
    private var owner: UUID?
    private var generation = UUID()
    private var requestedLimit = 50
    private var isReloading = false
    private var needsReload = false

    init(client: SupabaseClient? = nil) {
        self.client = client ?? SupabaseService.client
    }

    func observe(userID: UUID) async {
        let run = UUID()
        generation = run
        owner = userID
        requestedLimit = pageSize
        items = []
        sections = []
        unreadCount = 0
        unreadBulletinIDs = []
        unreadMessageCount = 0
        loading = true
        let channel = client.channel("notifications-\(userID)-\(run)")
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "notificaciones_app",
            filter: .eq("perfil_id", value: userID.uuidString)
        )
        await load(userID: userID)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                do {
                    try await channel.subscribeWithError()
                    for await _ in changes {
                        guard !Task.isCancelled else { break }
                        await self?.load(userID: userID)
                    }
                } catch {}
            }
            group.addTask { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(120)) } catch { break }
                    await self?.load(userID: userID)
                }
            }
            await group.waitForAll()
        }
        await client.removeChannel(channel)
        if generation == run {
            owner = nil
            items = []
            sections = []
        }
    }

    func select(filter newFilter: NotificationFilter) async {
        guard newFilter != filter, let owner else { return }
        filter = newFilter
        requestedLimit = pageSize
        items = []
        sections = []
        hasMore = false
        await load(userID: owner)
    }

    func load(userID: UUID) async {
        guard owner == userID else { return }
        if isReloading {
            needsReload = true
            return
        }
        isReloading = true
        let run = generation
        let selectedFilter = filter
        loading = items.isEmpty
        defer {
            isReloading = false
            if generation == run { loading = false }
            if needsReload, owner == userID {
                needsReload = false
                Task { await load(userID: userID) }
            }
        }
        do {
            let page = try await fetchPage(
                userID: userID,
                filter: selectedFilter,
                from: 0,
                to: requestedLimit - 1
            )
            guard !Task.isCancelled, generation == run, owner == userID, filter == selectedFilter else { return }
            items = page
            hasMore = page.count == requestedLimit
            rebuildSections()
            try await refreshCounts(userID: userID, run: run)
            failure = nil
        } catch {
            if !Task.isCancelled, generation == run {
                failure = AuthNotice.failure(error).message
            }
        }
    }

    func loadNextPage() async {
        guard let owner, hasMore, !loadingMore, !isReloading else { return }
        loadingMore = true
        let run = generation
        let selectedFilter = filter
        let offset = items.count
        defer { if generation == run { loadingMore = false } }
        do {
            let page = try await fetchPage(
                userID: owner,
                filter: selectedFilter,
                from: offset,
                to: offset + pageSize - 1
            )
            guard !Task.isCancelled, generation == run, self.owner == owner, filter == selectedFilter else { return }
            let known = Set(items.map(\.id))
            items += page.filter { !known.contains($0.id) }
            requestedLimit = items.count
            hasMore = page.count == pageSize
            rebuildSections()
            failure = nil
        } catch {
            if !Task.isCancelled, generation == run {
                failure = AuthNotice.failure(error).message
            }
        }
    }

    func markRead(_ id: UUID? = nil) async {
        guard let owner else { return }
        struct Params: Encodable { let p_id: UUID? }
        do {
            try await client.rpc("notifications_mark_read", params: Params(p_id: id)).execute()
            guard self.owner == owner else { return }
            if filter == .unread {
                items.removeAll { id == nil || $0.id == id }
            } else {
                for index in items.indices where id == nil || items[index].id == id {
                    items[index].leida = true
                }
            }
            rebuildSections()
            try await refreshCounts(userID: owner, run: generation)
            failure = nil
        } catch {
            failure = AuthNotice.failure(error).message
        }
    }

    func markBulletinRead(_ id: UUID) async {
        guard let owner else { return }
        do {
            let rows: [NotificationID] = try await client.from("notificaciones_app")
                .select("id")
                .eq("perfil_id", value: owner)
                .eq("destino_tipo", value: "comunicado")
                .eq("destino_id", value: id)
                .or("leida.eq.false,leida.is.null")
                .execute()
                .value
            struct Params: Encodable { let p_id: UUID? }
            for row in rows {
                guard !Task.isCancelled else { return }
                try await client.rpc("notifications_mark_read", params: Params(p_id: row.id)).execute()
            }
            for index in items.indices where items[index].destino_tipo == "comunicado" && items[index].destino_id == id {
                items[index].leida = true
            }
            if filter == .unread {
                items.removeAll { $0.destino_tipo == "comunicado" && $0.destino_id == id }
            }
            rebuildSections()
            try await refreshCounts(userID: owner, run: generation)
            failure = nil
        } catch {
            failure = AuthNotice.failure(error).message
        }
    }

    private func fetchPage(
        userID: UUID,
        filter: NotificationFilter,
        from: Int,
        to: Int
    ) async throws -> [EmployeeNotification] {
        let query = client.from("notificaciones_app")
            .select()
            .eq("perfil_id", value: userID)
        switch filter {
        case .all:
            break
        case .unread:
            query.or("leida.eq.false,leida.is.null")
        case .assignments:
            query.eq("destino_tipo", value: "asignacion")
        case .bulletins:
            query.eq("destino_tipo", value: "comunicado")
        }
        return try await query
            .order("fecha_creacion", ascending: false)
            .order("id")
            .range(from: from, to: to)
            .execute()
            .value
    }

    private func refreshCounts(userID: UUID, run: UUID) async throws {
        let unreadResponse = try await client.from("notificaciones_app")
            .select("id", head: true, count: .exact)
            .eq("perfil_id", value: userID)
            .or("leida.eq.false,leida.is.null")
            .execute()
        let bulletinRows: [BulletinUnread] = try await client.from("notificaciones_app")
            .select("destino_id,tipo")
            .eq("perfil_id", value: userID)
            .eq("destino_tipo", value: "comunicado")
            .or("leida.eq.false,leida.is.null")
            .execute()
            .value
        guard !Task.isCancelled, generation == run, owner == userID else { return }
        let deleted = Set(bulletinRows.filter { $0.tipo == "comunicado_eliminado" }.compactMap(\.destino_id))
        unreadBulletinIDs = Set(
            bulletinRows
                .filter { $0.tipo != "comunicado_eliminado" }
                .compactMap(\.destino_id)
        ).subtracting(deleted)
        unreadCount = unreadResponse.count ?? 0
        unreadMessageCount = unreadBulletinIDs.count
        try? await UNUserNotificationCenter.current().setBadgeCount(unreadCount)
    }

    private func rebuildSections(referenceDate: Date = Date()) {
        let calendar = Calendar.autoupdatingCurrent
        let relative = RelativeDateTimeFormatter()
        relative.locale = Locale(identifier: "es_DO")
        relative.unitsStyle = .abbreviated
        var result: [NotificationDaySection] = []
        var currentDay: Date?
        var currentTitle = ""
        var currentRows: [NotificationRow] = []
        func flush() {
            guard let currentDay else { return }
            result.append(NotificationDaySection(day: currentDay, title: currentTitle, rows: currentRows))
        }
        for item in items {
            let date = item.date
            let day = calendar.startOfDay(for: date)
            let row = NotificationRow(
                notification: item,
                timeLabel: relative.localizedString(for: date, relativeTo: referenceDate)
            )
            if currentDay != day {
                flush()
                currentDay = day
                currentTitle = dayTitle(day, calendar: calendar)
                currentRows = []
            }
            currentRows.append(row)
        }
        flush()
        sections = result
    }

    private func dayTitle(_ day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Hoy" }
        if calendar.isDateInYesterday(day) { return "Ayer" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}
