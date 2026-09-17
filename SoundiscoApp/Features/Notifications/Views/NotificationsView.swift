import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var auth: SessionViewModel
    @EnvironmentObject private var model: NotificationsViewModel
    @EnvironmentObject private var push: PushNotificationService

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(NotificationFilter.allCases) { filter in
                            Button { model.filter = filter } label: {
                                Text(filter.rawValue).font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(model.filter == filter ? Brand.red : Color(uiColor: .tertiarySystemFill), in: Capsule())
                                    .foregroundStyle(model.filter == filter ? Color.white : .primary)
                            }.buttonStyle(.plain)
                        }
                    }
                }.listRowBackground(Color.clear)
            }
            if push.permissionDenied {
                Button("Activar avisos en Ajustes", systemImage: "bell.slash") { push.openSettings() }
            }
            if let failure = model.failure {
                Section {
                    Text(failure).foregroundStyle(.secondary)
                    Button("Reintentar") { Task { await refresh() } }
                }
            }
            if let failure = push.failure { Text(failure).font(.footnote).foregroundStyle(.secondary) }
            if model.loading && model.items.isEmpty {
                ProgressView("Cargando notificaciones…")
            } else if model.filtered.isEmpty {
                ContentUnavailableView("Sin notificaciones", systemImage: "bell",
                    description: Text(model.filter == .unread ? "Estás al día." : "Los avisos aparecerán aquí."))
            } else {
                ForEach(days, id: \.self) { day in
                    Section(dayTitle(day)) {
                        ForEach(model.filtered.filter { Calendar.current.startOfDay(for: $0.date) == day }) { item in
                            NavigationLink { NotificationDestinationView(notificationID: item.id) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: item.symbol).foregroundStyle(Brand.red).frame(width: 32, height: 32)
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(alignment: .top) {
                                            Text(item.titulo ?? "Notificación").font(.headline)
                                            Spacer(minLength: 4)
                                            if item.unread { Circle().fill(Brand.red).frame(width: 8, height: 8) }
                                        }
                                        Text(item.mensaje ?? "").font(.subheadline).foregroundStyle(.secondary)
                                        Text(item.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                                    }
                                }.padding(.vertical, 8)
                            }
                            .swipeActions {
                                if item.unread {
                                    Button("Marcar leída", systemImage: "checkmark") {
                                        Task { await model.markRead(item.id) }
                                    }.tint(Brand.red)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Notificaciones")
        .toolbar {
            Button("Marcar todas leídas", systemImage: "checkmark.circle") { Task { await model.markRead() } }
                .disabled(model.unreadCount == 0)
        }
        .refreshable { await refresh() }
        .task { await push.requestPermission() }
    }
    private var days: [Date] {
        Set(model.filtered.map { Calendar.current.startOfDay(for: $0.date) }).sorted(by: >)
    }
    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Hoy" }
        if Calendar.current.isDateInYesterday(day) { return "Ayer" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
    private func refresh() async {
        if let id = auth.userID { await model.load(userID: id) }
    }
}
