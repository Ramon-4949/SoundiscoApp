import SwiftUI

struct AssignmentDetailView: View {
    @Environment(\.isAdministrator) private var isAdministrator
    @StateObject private var model: AssignmentDetailViewModel
    private let allowsChecklistUpdates: Bool

    init(assignment: Assignment, allowsChecklistUpdates: Bool = true) {
        self.allowsChecklistUpdates = allowsChecklistUpdates
        _model = StateObject(wrappedValue: AssignmentDetailViewModel(assignment: assignment))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if model.assignment.isField {
                    location
                } else {
                    deadline
                }
                if !model.assignment.milestones.isEmpty {
                    itinerary
                }
                responsiblePeople
                instructions
                if !model.assignment.milestones.isEmpty {
                    NavigationLink {
                        AssignmentChecklistView(model: model, allowsUpdates: allowsChecklistUpdates)
                    } label: {
                        HStack(spacing: 12) {
                            Label("Checklist", systemImage: "checklist").font(.headline)
                            Spacer()
                            Text("\(completedCount) / \(model.assignment.milestones.count)")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Abre el progreso de los hitos")
                }
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Detalle de asignación")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Brand.red)
        .toolbar {
            if isAdministrator {
                ToolbarItem(placement: .topBarTrailing) {
                    AdminAssignmentMenu(assignmentID: model.assignment.id) {
                        Task { await model.reload() }
                    }
                }
            }
        }
        .task { await model.reload() }
        .refreshable { await model.reload() }
        .alert("No se pudo actualizar", isPresented: errorBinding) {
            Button("Reintentar") { Task { await model.reload() } }
            Button("Cerrar", role: .cancel) { }
        } message: {
            Text(model.errorMessage ?? "Error desconocido")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ASIGNACIÓN").font(.caption.weight(.bold)).foregroundStyle(Brand.red)
                Text(model.assignment.titulo).font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Label(model.assignment.isField ? "Campo" : "Administrativa",
                          systemImage: model.assignment.isField ? "truck.box" : "doc.text")
                    Text((model.assignment.nivel_prioridad ?? "sin prioridad").capitalized)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: model.assignment.isField ? "truck.box" : "doc.text")
                .font(.title2).foregroundStyle(Brand.red)
                .frame(width: 48, height: 48)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
        }
        .detailSurface()
    }

    private var location: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("UBICACIÓN DEL EVENTO", systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.bold)).foregroundStyle(Brand.red)
            Text(model.assignment.ubicacion ?? "Ubicación por confirmar")
                .font(.headline).textSelection(.enabled)
        }
        .detailSurface()
    }

    private var deadline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("FECHA LÍMITE", systemImage: "calendar")
                .font(.caption.weight(.bold)).foregroundStyle(Brand.red)
            Text(model.assignment.deadline?.formatted(date: .long, time: .shortened) ?? "Por confirmar")
                .font(.headline)
        }
        .detailSurface()
    }

    private var itinerary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("CRONOGRAMA OPERATIVO", systemImage: "clock")
                .font(.caption.weight(.bold)).foregroundStyle(.secondary)
            ForEach(model.assignment.milestones) { milestone in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(AgendaDate.label(milestone.scheduleValue))
                        .font(.caption.weight(.semibold)).frame(width: 82, alignment: .leading)
                    Circle().fill(milestone.isCompleted ? Color.green : Brand.red)
                        .frame(width: 6, height: 6).accessibilityHidden(true)
                    Text(milestone.descripcion ?? "Hito")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .detailSurface()
    }

    private var responsiblePeople: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Responsables asignados", systemImage: "person.2").font(.headline)
            Text(model.assignment.responsibleNames.joined(separator: ", "))
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .detailSurface()
    }

    @ViewBuilder
    private var instructions: some View {
        if let instructions = model.assignment.instrucciones, !instructions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Instrucciones", systemImage: "info.circle.fill").font(.headline)
                Text(instructions).textSelection(.enabled)
            }
            .detailSurface()
        }
    }

    private var completedCount: Int {
        model.assignment.milestones.filter(\.isCompleted).count
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.clearError() } })
    }
}

private extension View {
    func detailSurface() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
