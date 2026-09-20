import SwiftUI

struct AssignmentChecklistView: View {
    @ObservedObject var model: AssignmentDetailViewModel
    let allowsUpdates: Bool
    @State private var notes = ""
    @State private var alertMessage: String?
    @State private var now = Date()
    @FocusState private var notesFocused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.assignment.milestones.enumerated()), id: \.element.id) { index, milestone in
                    milestoneRow(milestone, index: index)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Checklist")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Brand.red)
        .safeAreaInset(edge: .bottom) {
            if isExpired {
                Label("Asignación vencida", systemImage: "lock.fill")
                    .font(.headline).foregroundStyle(Brand.red)
                    .frame(maxWidth: .infinity).padding().background(.bar)
            } else if allCompleted {
                Label("Asignación completada", systemImage: "checkmark.seal.fill")
                    .font(.headline).foregroundStyle(.green)
                    .frame(maxWidth: .infinity).padding().background(.bar)
            }
        }
        .alert("No se pudo completar el hito", isPresented: alertBinding) {
            Button("Aceptar", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "Error desconocido")
        }
        .task {
            while !Task.isCancelled {
                now = .now
                do { try await Task.sleep(for: .seconds(15)) }
                catch { break }
            }
        }
    }

    private func milestoneRow(_ milestone: Milestone, index: Int) -> some View {
        let state = state(for: index)
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                milestoneIcon(state: state, index: index)
                if index < model.assignment.milestones.count - 1 {
                    Rectangle().fill(Color(uiColor: .separator))
                        .frame(width: 2)
                        .frame(minHeight: state == .current ? 190 : 58)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(milestone.descripcion ?? "Hito").font(.headline)
                    Spacer()
                    Text(AgendaDate.label(milestone.scheduleValue))
                        .font(.caption).foregroundStyle(.secondary)
                }

                if state == .completed {
                    Label("Completado", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                    if let savedNotes = milestone.notas_incidencias, !savedNotes.isEmpty {
                        Text(savedNotes).font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if isExpired {
                    Label("La fecha límite venció. Este checklist está bloqueado.", systemImage: "lock.fill")
                        .font(.subheadline).foregroundStyle(Brand.red)
                } else if state == .current && allowsUpdates {
                    TextField("Notas o incidencias (opcional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6).focused($notesFocused).padding(12)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    Button {
                        Task { await confirm(milestone) }
                    } label: {
                        HStack {
                            Spacer()
                            if model.savingMilestoneID == milestone.id { ProgressView().tint(.white) }
                            Label(model.savingMilestoneID == milestone.id ? "Confirmando…" : "Confirmar hito",
                                  systemImage: "checkmark.circle")
                            Spacer()
                        }
                        .font(.headline).padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.red)
                    .disabled(model.savingMilestoneID != nil)
                } else if state == .locked {
                    Label("Se habilitará al completar el paso anterior", systemImage: "lock")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Label("Hito en curso", systemImage: "clock")
                        .font(.subheadline).foregroundStyle(Brand.red)
                }
            }
            .padding(.bottom, 22)
            .opacity(state == .locked ? 0.62 : 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func milestoneIcon(state: ChecklistState, index: Int) -> some View {
        Group {
            switch state {
            case .completed:
                Image(systemName: "checkmark").foregroundStyle(.green)
            case .current:
                Text("\(index + 1)").foregroundStyle(.white).font(.headline)
            case .locked:
                Image(systemName: "lock").foregroundStyle(.secondary)
            }
        }
        .frame(width: 36, height: 36)
        .background(state == .current ? Brand.red : Color(uiColor: .tertiarySystemFill), in: Circle())
    }

    private func state(for index: Int) -> ChecklistState {
        let milestones = model.assignment.milestones
        if milestones[index].isCompleted { return .completed }
        let previousAreComplete = milestones[..<index].allSatisfy(\.isCompleted)
        return previousAreComplete ? .current : .locked
    }

    private var allCompleted: Bool {
        !model.assignment.milestones.isEmpty && model.assignment.milestones.allSatisfy(\.isCompleted)
    }

    private var isExpired: Bool {
        model.assignment.overdue(at: now)
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
    }

    private func confirm(_ milestone: Milestone) async {
        notesFocused = false
        do {
            try await model.complete(milestone, notes: notes)
            notes = ""
        } catch {
            alertMessage = error.localizedDescription
            model.clearError()
        }
    }
}

private enum ChecklistState {
    case completed
    case current
    case locked
}
