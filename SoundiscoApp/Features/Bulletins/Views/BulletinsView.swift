import SwiftUI

struct BulletinsView: View {
    @EnvironmentObject private var notifications: NotificationsViewModel
    @Environment(\.isAdministrator) private var isAdministrator
    @StateObject private var model = BulletinsViewModel()
    @State private var creating = false
    @State private var search = ""
    @State private var unreadOnly = false

    private var visibleItems: [Bulletin] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.items.filter { item in
            (!unreadOnly || notifications.unreadBulletinIDs.contains(item.id)) &&
            (query.isEmpty || item.asunto.localizedStandardContains(query) ||
                item.mensaje.localizedStandardContains(query))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                searchField
                if unreadOnly {
                    Label("Sin revisar", systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.red)
                }
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .task { await model.load() }
        .refreshable { await model.load() }
        .sheet(isPresented: $creating, onDismiss: { Task { await model.load() } }) {
            NavigationStack { AdminMessageComposerView(onComplete: {}) }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    title
                    unreadBadge
                }
                VStack(alignment: .leading, spacing: 6) {
                    title
                    unreadBadge
                }
            }
            Spacer(minLength: 4)
            Menu {
                if isAdministrator {
                    Button("Crear comunicado", systemImage: "square.and.pencil") { creating = true }
                    Divider()
                }
                Button(unreadOnly ? "Ver todos" : "Ver sin revisar",
                       systemImage: unreadOnly ? "tray.full" : "envelope.badge") {
                    unreadOnly.toggle()
                }
                Button("Actualizar", systemImage: "arrow.clockwise") {
                    Task { await model.load() }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.05), lineWidth: 1))
                    .shadow(color: .black.opacity(0.04), radius: 2, y: 2)
            }
            .accessibilityLabel("Opciones de mensajes")
        }
    }

    private var title: some View {
        Text("Mensajes")
            .font(.largeTitle.bold())
            .foregroundStyle(.primary)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var unreadBadge: some View {
        if notifications.unreadMessageCount > 0 {
            Text("\(notifications.unreadMessageCount) \(notifications.unreadMessageCount == 1 ? "nuevo" : "nuevos")")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Brand.red, in: Capsule())
                .fixedSize()
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Buscar avisos o montajes…", text: $search)
                .font(.body)
                .foregroundStyle(.primary)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Buscar mensajes")
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Borrar búsqueda")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.07), lineWidth: 1))
        .shadow(color: .black.opacity(0.03), radius: 2, y: 2)
    }

    @ViewBuilder
    private var content: some View {
        if model.loading && model.items.isEmpty {
            ProgressView("Cargando mensajes…")
                .frame(maxWidth: .infinity)
                .padding(.top, 36)
        } else if let failure = model.failure {
            ContentUnavailableView {
                Label("No se pudieron cargar los mensajes", systemImage: "wifi.exclamationmark")
            } description: {
                Text(failure)
            } actions: {
                Button("Reintentar") { Task { await model.load() } }
            }
        } else if visibleItems.isEmpty {
            ContentUnavailableView(
                search.isEmpty ? (unreadOnly ? "Estás al día" : "Sin mensajes") : "Sin resultados",
                systemImage: search.isEmpty ? "tray" : "magnifyingglass",
                description: Text(search.isEmpty ? "No hay comunicados pendientes para mostrar." : "Prueba con otro texto.")
            )
        } else {
            LazyVStack(spacing: 22) {
                ForEach(visibleItems) { item in
                    NavigationLink {
                        BulletinDetailView(bulletin: item)
                            .toolbar(.visible, for: .navigationBar)
                    } label: {
                        BulletinMessageCard(
                            bulletin: item,
                            unread: notifications.unreadBulletinIDs.contains(item.id)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct BulletinMessageCard: View {
    let bulletin: Bulletin
    let unread: Bool

    private var dateLabel: String {
        guard let date = AgendaDate.parse(bulletin.fecha_publicacion) else { return "Sin fecha" }
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "Hoy, \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "Ayer, \(time)" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(unread ? Brand.red : Color(uiColor: .separator).opacity(0.35))
                .frame(height: 4)
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        status
                        Spacer(minLength: 8)
                        timestamp
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        status
                        timestamp
                    }
                }
                Text(bulletin.asunto)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(bulletin.mensaje)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
                    .lineLimit(2)
                Divider().padding(.top, 10)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        readingStatus
                        Spacer(minLength: 12)
                        detailLabel
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        readingStatus
                        detailLabel
                    }
                }
                .padding(.top, 2)
            }
            .padding(18)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.05), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    private var status: some View {
        HStack(spacing: 5) {
            if unread {
                Circle().fill(Brand.red).frame(width: 6, height: 6)
            } else {
                Image(systemName: "checkmark").font(.caption2.bold())
            }
            Text(unread ? "NUEVO" : "LEÍDO").font(.caption.bold())
        }
        .foregroundStyle(unread ? Brand.red : Color.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(unread ? Brand.red.opacity(0.06) : Color(uiColor: .tertiarySystemFill), in: Capsule())
        .overlay(Capsule().stroke(unread ? Brand.red.opacity(0.14) : Color.clear, lineWidth: 1))
        .fixedSize()
    }

    private var timestamp: some View {
        Text(dateLabel)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var readingStatus: some View {
        Label(unread ? "Pendiente de lectura" : "Revisado", systemImage: unread ? "envelope.badge" : "checkmark.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(MessageStatusLabelStyle())
            .fixedSize()
    }

    private var detailLabel: some View {
        HStack(spacing: 8) {
            Text("Ver detalles").font(.subheadline.weight(.semibold))
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
        }
        .foregroundStyle(Brand.red)
        .fixedSize()
    }
}

private struct MessageStatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(.green)
            configuration.title
        }
    }
}

#Preview("Mensaje nuevo") {
    BulletinMessageCard(
        bulletin: Bulletin(
            id: UUID(),
            asunto: "Ajuste de tiempos: Montaje y prueba de sala B",
            mensaje: "Se adelanta la prueba de sonido FOH a las 17:00 hrs debido a requerimientos de producción.",
            fecha_publicacion: ISO8601DateFormatter().string(from: Date())
        ),
        unread: true
    )
    .padding(20)
    .background(Color(uiColor: .systemGroupedBackground))
}
