import SwiftUI

struct AssignmentListView: View {
    @EnvironmentObject private var auth: SessionViewModel
    @ObservedObject var agenda: AssignmentsViewModel
    @State private var searching = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("CENTRO DE ASIGNACIONES", systemImage: "circle.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(Brand.red)
                        Text("Hola, \(auth.displayName)").font(.largeTitle.bold())
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text("Asignaciones actuales").font(.title3.bold())
                        Spacer()
                        Button("Ver todas (\(agenda.assignments.count))") { agenda.filter = .all; agenda.search = "" }
                            .font(.subheadline)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 18) {
                            ForEach(AssignmentFilter.allCases, id: \.self) { option in
                                Button { agenda.filter = option } label: {
                                    VStack(spacing: 8) {
                                        Text(option.rawValue).font(.subheadline.weight(agenda.filter == option ? .semibold : .regular))
                                        Rectangle().fill(agenda.filter == option ? Brand.red : .clear).frame(height: 3)
                                    }.padding(.top, 10)
                                }
                                .foregroundStyle(agenda.filter == option ? Brand.red : .secondary)
                                .accessibilityAddTraits(agenda.filter == option ? .isSelected : [])
                            }
                        }
                    }
                    if agenda.loading && agenda.assignments.isEmpty {
                        ProgressView("Cargando asignaciones…").frame(maxWidth: .infinity).padding(40)
                    } else if let error = agenda.error {
                        ContentUnavailableView {
                            Label("No se pudieron cargar", systemImage: "wifi.exclamationmark")
                        } description: { Text(error) } actions: {
                            Button("Reintentar") { Task { await reload() } }
                        }
                    } else if agenda.filtered(at: context.date).isEmpty {
                        ContentUnavailableView("Sin asignaciones", systemImage: "tray", description:
                            Text(agenda.search.isEmpty && agenda.filter == .all ? "Tus asignaciones aparecerán aquí cuando te incluyan en un equipo." : "No hay asignaciones que coincidan con este filtro."))
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(agenda.filtered(at: context.date)) { assignment in
                                NavigationLink { AssignmentDetailView(assignment: assignment) } label: {
                                    AssignmentCard(assignment: assignment, now: context.date)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .refreshable { await reload() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $agenda.search, isPresented: $searching, prompt: "Buscar asignaciones")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink { NotificationsView() } label: { Image(systemName: "bell") }
                    .accessibilityLabel("Notificaciones")
                Button { searching.toggle() } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Buscar")
            }
        }
    }

    private func reload() async { if let id = auth.userID { await agenda.load(userID: id) } }
}
