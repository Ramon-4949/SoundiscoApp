import SwiftUI

struct AgendaCalendarView: View {
    @EnvironmentObject private var auth: SessionViewModel
    @Environment(\.isAdministrator) private var isAdministrator
    @StateObject private var agenda = AssignmentsViewModel()
    @StateObject private var model = CalendarViewModel()
    var isActive = true
    var refreshRevision = 0

    private var observation: AssignmentFeedObservation {
        AssignmentFeedObservation(query: auth.userID.map {
            AssignmentFeedQuery(userID: $0, filter: .all, day: model.selected, personalized: !isAdministrator)
        }, isActive: isActive, revision: refreshRevision)
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                DatePicker("Fecha", selection: $model.selected, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .id("day-agenda")
                Section("Agenda del día") {
                    if agenda.loading && agenda.assignments.isEmpty {
                        ProgressView("Cargando agenda…")
                    }
                    if let error = agenda.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("No se pudo cargar la agenda", systemImage: "wifi.exclamationmark")
                            Text(error).font(.footnote).foregroundStyle(.secondary)
                            Button("Reintentar") { Task { await agenda.retry() } }
                        }
                    } else if !agenda.loading && agenda.assignments.isEmpty {
                        Text("Sin asignaciones con fecha para este día.").foregroundStyle(.secondary)
                    }
                    ForEach(agenda.assignments) { item in
                        NavigationLink(item.titulo) { AssignmentDetailView(assignment: item) }
                    }
                    if agenda.hasMore || agenda.pageIndex > 0 {
                        AssignmentPaginationControls(pageIndex: agenda.pageIndex, hasMore: agenda.hasMore,
                            loading: agenda.loading,
                            previous: { Task { await agenda.previousPage(); proxy.scrollTo("day-agenda", anchor: .top) } },
                            next: { Task { await agenda.nextPage(); proxy.scrollTo("day-agenda", anchor: .top) } })
                    }
                }
            }
            .refreshable { await agenda.refresh() }
        }
        .navigationTitle("Calendario")
        .tint(Brand.red)
        .task(id: observation) {
            guard observation.isActive, let query = observation.query else { agenda.pause(); return }
            await agenda.observe(query: query)
        }
    }
}
