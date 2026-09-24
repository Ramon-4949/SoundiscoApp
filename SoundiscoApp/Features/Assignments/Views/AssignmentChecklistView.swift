import SwiftUI

struct AssignmentChecklistView: View {
    @ObservedObject var model: AssignmentDetailViewModel
    let allowsUpdates: Bool
    @State private var failure: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let error = model.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.subheadline).foregroundStyle(.secondary)
                        Button("Reintentar") { Task { await model.reload() } }
                    }.padding(.bottom, 24)
                }
                ForEach(Array(model.assignment.milestones.enumerated()), id: \.element.id) { index, milestone in
                    timelineRow(milestone, index: index, now: context.date)
                }
            }
            .padding(.horizontal, 20).padding(.top, 32).padding(.bottom, 28)
            .frame(maxWidth: 680).frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        }
        .navigationTitle("Checklist").navigationBarTitleDisplayMode(.inline).tint(Brand.red)
        .refreshable { await model.reload() }
        .task { await model.observe() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.reload() } }
        }
        .alert("No se pudo confirmar", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: { Text(failure ?? "") }
    }

    private func timelineRow(_ milestone: Milestone, index: Int, now: Date) -> some View {
        let people = milestone.hitos_colaboradores ?? []
        let own = people.first { $0.usuario_id == model.userID }
        let confirmed = milestone.isCompleted
        let block = model.checkInBlock(milestone, at: now)
        let locked = own != nil && own?.confirmado != true && block != nil
        return HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle().fill(confirmed || locked ? Color(uiColor: .tertiarySystemFill) : Brand.red)
                if confirmed {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.primary)
                } else if locked {
                    Image(systemName: "lock.fill").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("\(index + 1)").font(.headline).foregroundStyle(.white)
                }
            }
            .frame(width: 40, height: 40)
            .shadow(color: confirmed || locked ? .clear : Brand.red.opacity(0.22), radius: 5, y: 3)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(milestone.descripcion ?? "Hito").font(.headline)
                        Spacer(minLength: 8)
                        Text(timeLabel(milestone)).font(.caption).foregroundStyle(.secondary).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(milestone.descripcion ?? "Hito").font(.headline)
                        Text(timeLabel(milestone)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !people.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(people.sorted { ($0.perfiles?.nombre ?? "") < ($1.perfiles?.nombre ?? "") }) { person in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: person.confirmado ? "checkmark" : "clock")
                                    .foregroundStyle(person.confirmado ? Color.green : Brand.red)
                                Text(person.perfiles?.nombre ?? "Colaborador")
                                    .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                                Text(person.etiqueta).font(.caption2.weight(.medium))
                                    .foregroundStyle(evaluationColor(person.estado))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(evaluationColor(person.estado).opacity(0.1), in: Capsule())
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }.padding(12)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                }
                if own?.confirmado == true {
                    Label("Confirmado", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                } else if own != nil, let block {
                    Text(block)
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if !confirmed {
                    Text("En Curso")
                        .font(.caption.weight(.semibold)).foregroundStyle(Brand.red)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Brand.red.opacity(0.10), in: Capsule())
                    if allowsUpdates && own != nil {
                        Button {
                            Task {
                                do { try await model.complete(milestone) }
                                catch { failure = error.localizedDescription; model.clearError() }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if model.savingMilestoneID == milestone.id { ProgressView().tint(.white) }
                                Label(model.savingMilestoneID == milestone.id ? "Confirmando…" : "Confirmar hito",
                                      systemImage: "checkmark.circle")
                            }
                            .font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent).tint(Brand.red)
                        .disabled(model.savingMilestoneID != nil || block != nil)
                    }
                }
            }
            .foregroundStyle(locked ? .secondary : .primary)
            .padding(.top, 5).padding(.bottom, 32)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        }
        .background(alignment: .topLeading) {
            if index < model.assignment.milestones.count - 1 {
                GeometryReader { geometry in
                    Rectangle().fill(Color(uiColor: .separator).opacity(0.5))
                        .frame(width: 2, height: max(0, geometry.size.height - 20))
                        .offset(x: 19, y: 20)
                }
            }
        }
    }

    private func timeLabel(_ milestone: Milestone) -> String {
        if let date = AgendaDate.parse(milestone.fecha_programada) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return AgendaDate.label(milestone.scheduleValue)
    }

    private func evaluationLabel(_ evaluation: String) -> String {
        switch evaluation {
        case "temprano": "Confirmación temprana"
        case "a_tiempo": "A tiempo"
        default: "Confirmación tardía"
        }
    }

    private func evaluationColor(_ evaluation: String) -> Color {
        switch evaluation {
        case "temprano": .green
        case "a_tiempo": .secondary
        case "tardio": .orange
        default: .secondary
        }
    }
}
