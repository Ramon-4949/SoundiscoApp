import SwiftUI

struct AgendaCalendarView: View {
    @ObservedObject var agenda: AssignmentsViewModel
    @StateObject private var model = CalendarViewModel()
    var body: some View {
        List {
            DatePicker("Fecha", selection: $model.selected, displayedComponents: .date).datePickerStyle(.graphical)
            Section("Agenda del día") {
                let entries = model.entries(in: agenda.assignments)
                if entries.isEmpty { Text("Sin asignaciones con fecha para este día.").foregroundStyle(.secondary) }
                ForEach(entries) { item in
                    NavigationLink(item.titulo) { AssignmentDetailView(assignment: item) }
                }
            }
        }.navigationTitle("Calendario")
    }
}
