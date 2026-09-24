import SwiftUI

struct AssignmentCard: View {
    let assignment: Assignment
    var now: Date = .now
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            let layout = textSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            layout {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: assignment.isField ? "truck.box" : "doc.text")
                        .font(.title2).foregroundStyle(.white).frame(width: 46, height: 46)
                        .background(Brand.red, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 3) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { category; priority }
                            VStack(alignment: .leading, spacing: 4) { category; priority }
                        }
                        Text(assignment.titulo).font(.headline).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                statusBadge
            }

            VStack(alignment: .leading, spacing: 10) {
                if assignment.isField {
                    if let milestone = assignment.nextMilestone {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "clock").foregroundStyle(Brand.red)
                            Text(AgendaDate.label(milestone.scheduleValue)).foregroundStyle(.primary)
                            Text(milestone.descripcion ?? "Hito").foregroundStyle(.secondary)
                        }
                    }
                    Label(assignment.ubicacion ?? "Ubicación por confirmar", systemImage: "mappin.and.ellipse")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "clock").foregroundStyle(Brand.red)
                        Text(assignment.deadline.map { "Hasta \($0.formatted(date: .abbreviated, time: .shortened))" }
                             ?? "Fecha límite por confirmar").foregroundStyle(.primary)
                    }
                }
            }
            .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Text("Detalle")
                Image(systemName: "arrow.right")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.subheadline).foregroundStyle(Brand.red)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.03)))
    }

    private var category: some View {
        Text(assignment.isField ? "Campo" : "Oficina").font(.caption).foregroundStyle(.secondary)
    }

    private var priority: some View {
        Text((assignment.nivel_prioridad ?? "Sin prioridad").uppercased())
            .font(.caption2.bold()).foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Brand.red, in: RoundedRectangle(cornerRadius: 4))
    }

    private var state: String {
        if assignment.completed { return "Completada" }
        if assignment.overdue(at: now) { return "Vencida" }
        return assignment.inProgress ? "En curso" : "Pendiente"
    }

    private var stateColor: Color {
        switch state {
        case "Completada": .green
        case "Vencida": .red
        case "En curso": .blue
        default: .yellow
        }
    }

    private var statusBadge: some View {
        Text(state).font(.caption.weight(.semibold))
            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black.opacity(0.85))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(stateColor.opacity(colorScheme == .dark ? 0.32 : 0.19), in: Capsule())
            .fixedSize()
    }
}
