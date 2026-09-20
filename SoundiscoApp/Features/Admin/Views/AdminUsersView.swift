import SwiftUI

struct AdminUsersView: View {
    @StateObject private var model = AdminUsersViewModel()
    @State private var rejecting: ManagedAccount?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Buscar por nombre, email o cargo…", text: $model.search)
                        .autocorrectionDisabled()
                    if !model.search.isEmpty {
                        Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("Borrar búsqueda")
                    }
                }.padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))

                Picker("Estado de acceso", selection: $model.filter) {
                    ForEach(AccountAccessState.allCases) { state in
                        Text(state == .pendiente ? "Pendientes (\(model.pendingCount))" : state.title).tag(state)
                    }
                }.pickerStyle(.segmented)

                if model.loading && model.users.isEmpty { ProgressView("Cargando usuarios…") }
                if let error = model.error {
                    Text(error).foregroundStyle(.secondary)
                    Button("Reintentar") { Task { await model.load() } }
                } else if !model.loading && model.filtered.isEmpty {
                    ContentUnavailableView("No hay usuarios", systemImage: "person.2", description: Text("No hay cuentas que coincidan con este filtro."))
                }
                ForEach(model.filtered) { user in accountRow(user) }
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Accesos").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar).tint(Brand.red)
        .task {
            await model.load()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                await model.load()
            }
        }
        .refreshable { await model.load() }
        .confirmationDialog("¿Rechazar el acceso?", isPresented: Binding(get: { rejecting != nil }, set: { if !$0 { rejecting = nil } }), titleVisibility: .visible) {
            if let user = rejecting {
                Button("Rechazar acceso", role: .destructive) {
                    rejecting = nil
                    Task { await model.decide(user, approved: false) }
                }
            }
            Button("Cancelar", role: .cancel) { rejecting = nil }
        } message: { Text("El usuario no podrá acceder a las asignaciones ni a los comunicados.") }
    }

    private func accountRow(_ user: ManagedAccount) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 48)).foregroundStyle(.tertiary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(user.displayName).font(.headline)
                    Text(user.email ?? "Sin correo").font(.subheadline).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(user.fecha, style: .relative).font(.caption).foregroundStyle(.secondary)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack { badge(user.cargo ?? "Sin cargo", icon: "person.badge.key"); badge(user.telefono ?? "Sin teléfono", icon: "phone") }
                VStack(alignment: .leading) { badge(user.cargo ?? "Sin cargo", icon: "person.badge.key"); badge(user.telefono ?? "Sin teléfono", icon: "phone") }
            }
            if user.estado != .aprobada {
                HStack(spacing: 12) {
                    if user.estado == .pendiente {
                        Button { rejecting = user } label: {
                            Label("Rechazar", systemImage: "xmark").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).tint(.primary)
                    }
                    Button { Task { await model.decide(user, approved: true) } } label: {
                        HStack {
                            if model.savingID == user.id { ProgressView().tint(.white) }
                            Label("Aprobar", systemImage: "checkmark")
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(Brand.red)
                }.controlSize(.large).disabled(model.savingID != nil)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func badge(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.subheadline)
            .padding(8).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
    }
}
