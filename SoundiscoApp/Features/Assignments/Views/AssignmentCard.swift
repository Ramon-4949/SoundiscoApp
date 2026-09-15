import SwiftUI

struct AssignmentCard: View {
    let assignment: Assignment
    var now: Date = .now
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: assignment.isField ? "truck.box" : "doc.text")
                    .font(.title2).foregroundStyle(.white).frame(width: 48, height: 48)
                    .background(Color(red: 0.76, green: 0, blue: 0.09), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    Text(assignment.isField ? "Campo" : "Administrativa").font(.caption).foregroundStyle(.secondary)
                    Text(assignment.titulo).font(.headline).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Text((assignment.nivel_prioridad ?? "Sin prioridad").capitalized).foregroundStyle(Brand.red)
                Spacer()
                Label(assignment.status(at: now), systemImage: assignment.completed ? "checkmark.circle.fill" : "clock")
                    .foregroundStyle(assignment.completed ? Color.green : Color.primary)
            }.font(.caption.weight(.semibold))
            Divider()
            if assignment.isField {
                if let milestone = assignment.nextMilestone {
                    Label("\(AgendaDate.label(milestone.scheduleValue)) · \(milestone.descripcion ?? "Hito")", systemImage: "clock")
                }
                Label(assignment.ubicacion ?? "Ubicación por confirmar", systemImage: "mappin.and.ellipse")
                    .foregroundStyle(.secondary)
            } else {
                Label(assignment.deadline.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Fecha límite por confirmar", systemImage: "calendar")
            }
            HStack { Text("Detalle"); Spacer(); Image(systemName: "chevron.right") }
                .font(.subheadline.weight(.medium)).foregroundStyle(Brand.red)
        }
        .font(.subheadline).padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
