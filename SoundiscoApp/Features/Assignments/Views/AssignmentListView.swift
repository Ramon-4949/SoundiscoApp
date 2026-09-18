import SwiftUI

struct AssignmentListView: View {
    @EnvironmentObject private var auth: SessionViewModel
    @ObservedObject var agenda: AssignmentsViewModel
    @State private var searching = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AgendaHomeHeader(name: auth.displayName, searching: $searching)
                    if searching { AgendaSearchField(text: $agenda.search) }
                    HStack(alignment: .firstTextBaseline) {
                        Text("Asignaciones actuales").font(.title3.bold())
                        Spacer()
                        Button("Ver todas (\(agenda.assignments.count))") { agenda.filter = .all; agenda.search = "" }
                            .font(.subheadline)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(AssignmentFilter.allCases, id: \.self) { option in
                                AgendaFilterPill(title: option.rawValue, selected: agenda.filter == option) {
                                    agenda.filter = option
                                }
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
                                NavigationLink {
                                    AssignmentDetailView(assignment: assignment)
                                        .toolbar(.visible, for: .navigationBar)
                                } label: {
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
        .toolbar(.hidden, for: .navigationBar)
        .tint(Brand.red)
        .onChange(of: searching) { _, visible in if !visible { agenda.search = "" } }
    }

    private func reload() async { if let id = auth.userID { await agenda.load(userID: id) } }
}
