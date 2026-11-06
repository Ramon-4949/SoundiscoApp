import SwiftUI

struct AssignmentListView: View {
    @EnvironmentObject private var auth: SessionViewModel
    @ObservedObject var agenda: AssignmentsViewModel
    var isActive = true
    var refreshRevision = 0
    @State private var searching = false
    @State private var filter = AssignmentFilter.pending

    private var observation: AssignmentFeedObservation {
        AssignmentFeedObservation(query: auth.userID.map {
            AssignmentFeedQuery(userID: $0, filter: filter, search: agenda.search)
        }, isActive: isActive, revision: refreshRevision)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        AgendaHomeHeader(name: auth.displayName, searching: $searching)
                        if searching { AgendaSearchField(text: $agenda.search) }
                        Text("Asignaciones").font(.title3.bold()).id("assignment-page")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(AssignmentFilter.homeOptions, id: \.self) { option in
                                    AgendaFilterPill(title: option.rawValue, selected: filter == option) { filter = option }
                                }
                            }
                        }
                        if agenda.loading && agenda.assignments.isEmpty {
                            ProgressView("Cargando asignaciones…").frame(maxWidth: .infinity).padding(40)
                        }
                        if let error = agenda.error {
                            ContentUnavailableView {
                                Label("No se pudieron cargar", systemImage: "wifi.exclamationmark")
                            } description: { Text(error) } actions: {
                                Button("Reintentar") { Task { await agenda.retry() } }
                            }
                        } else if !agenda.loading && agenda.assignments.isEmpty {
                            ContentUnavailableView("Sin asignaciones", systemImage: "tray", description:
                                Text("No hay asignaciones que coincidan con el filtro y la búsqueda."))
                        }
                        LazyVStack(spacing: 16) {
                            ForEach(agenda.assignments) { assignment in
                                NavigationLink {
                                    AssignmentDetailView(assignment: assignment)
                                        .toolbar(.visible, for: .navigationBar)
                                } label: { AssignmentCard(assignment: assignment, now: context.date) }
                                    .buttonStyle(.plain)
                            }
                        }
                        if agenda.hasMore || agenda.pageIndex > 0 {
                            AssignmentPaginationControls(pageIndex: agenda.pageIndex, hasMore: agenda.hasMore,
                                loading: agenda.loading,
                                previous: { Task { await agenda.previousPage(); proxy.scrollTo("assignment-page", anchor: .top) } },
                                next: { Task { await agenda.nextPage(); proxy.scrollTo("assignment-page", anchor: .top) } })
                        }
                    }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .refreshable { await agenda.refresh() }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(Brand.red)
        .onChange(of: searching) { _, visible in if !visible { agenda.search = "" } }
        .task(id: observation) {
            guard observation.isActive, let query = observation.query else { agenda.pause(); return }
            await agenda.observe(query: query)
        }
    }
}
