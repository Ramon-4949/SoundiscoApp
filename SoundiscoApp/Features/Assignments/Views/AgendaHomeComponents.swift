import SwiftUI

struct AgendaHomeHeader: View {
    let name: String
    @Binding var searching: Bool
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle().fill(Brand.red).frame(width: 7, height: 7)
                    Text("CENTRO DE ASIGNACIONES")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text("Hola, \(name)").font(.title.bold())
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            NavigationLink { NotificationsView().toolbar(.visible, for: .navigationBar) } label: {
                NotificationBell().labelStyle(.iconOnly)
                    .font(.title3).foregroundStyle(.secondary).frame(width: 36, height: 44)
            }.buttonStyle(.plain)
            Button { withAnimation { searching.toggle() } } label: {
                Image(systemName: searching ? "xmark" : "magnifyingglass")
                    .font(.title3).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Brand.red, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(searching ? "Cerrar búsqueda" : "Buscar asignaciones")
        }
    }
}

struct AgendaSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Buscar asignaciones", text: $text).focused($focused)
                .autocorrectionDisabled().submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.accessibilityLabel("Borrar búsqueda")
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .onAppear { focused = true }
    }
}

struct AgendaFilterPill: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 15).padding(.vertical, 9)
                .foregroundStyle(selected ? Color(uiColor: .systemBackground) : .secondary)
                .background(selected ? Color.primary : Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
