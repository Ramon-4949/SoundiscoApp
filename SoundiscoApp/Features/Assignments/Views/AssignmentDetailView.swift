import SwiftUI

struct AssignmentDetailView: View {
    let assignment: Assignment
    var body: some View {
        List {
            Section {
                Text(assignment.titulo).font(.title2.bold())
                LabeledContent("Tipo", value: assignment.isField ? "Campo" : "Administrativa")
                LabeledContent("Prioridad", value: assignment.nivel_prioridad ?? "Sin prioridad")
            }
            if let instructions = assignment.instrucciones, !instructions.isEmpty {
                Section("Instrucciones") { Text(instructions) }
            }
            if assignment.isField {
                Section("Ubicación") { Text(assignment.ubicacion ?? "Por confirmar") }
                Section("Itinerario") {
                    if assignment.milestones.isEmpty { Text("Sin hitos programados").foregroundStyle(.secondary) }
                    ForEach(assignment.milestones) { milestone in
                        HStack(alignment: .top) {
                            Image(systemName: milestone.completado == true ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(milestone.completado == true ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(milestone.descripcion ?? "Hito")
                                Text(AgendaDate.label(milestone.scheduleValue)).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Section("Fecha límite") { Text(assignment.deadline.map { $0.formatted(date: .long, time: .shortened) } ?? "Por confirmar") }
            }
        }.navigationTitle("Asignación").navigationBarTitleDisplayMode(.inline)
    }
}
