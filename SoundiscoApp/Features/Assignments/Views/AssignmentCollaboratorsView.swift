import SwiftUI

struct AssignmentCollaborator: Decodable, Identifiable {
    let id: UUID
    let nombre: String
    let cargo: String
    let es_supervisor: Bool

    var initials: String {
        nombre.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

struct AssignmentCollaboratorsSummary: View {
    @ObservedObject var model: AssignmentDetailViewModel

    private var featured: AssignmentCollaborator? { model.collaborators.first }
    private var remaining: [AssignmentCollaborator] { Array(model.collaborators.dropFirst()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("COLABORADORES ASIGNADOS", systemImage: "person.text.rectangle")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let featured {
                CollaboratorRow(person: featured)
                    .padding(12)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            } else if model.collaboratorsLoading {
                ProgressView("Cargando colaboradores…")
            } else if model.collaboratorsError != nil {
                Text("No se pudo cargar el equipo.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Sin colaboradores asignados").font(.subheadline).foregroundStyle(.secondary)
            }
            NavigationLink {
                AssignmentCollaboratorsView(model: model)
            } label: {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { preview; Spacer(minLength: 0); listLabel }
                    VStack(alignment: .leading, spacing: 12) { preview; listLabel }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ver lista de colaboradores asignados")
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var preview: some View {
        HStack(spacing: 10) {
            if !remaining.isEmpty {
                HStack(spacing: -10) {
                    ForEach(Array(remaining.prefix(2))) { person in
                        CollaboratorAvatar(person: person, size: 32)
                            .overlay(Circle().stroke(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 2))
                    }
                    if remaining.count > 2 {
                        Text("+\(remaining.count - 2)").font(.caption2.bold())
                            .foregroundStyle(Brand.red).frame(width: 32, height: 32)
                            .background(Brand.red.opacity(0.13), in: Circle())
                    }
                }.accessibilityHidden(true)
            }
            Text(remaining.isEmpty ? "Equipo asignado" : "\(remaining.count) \(remaining.count == 1 ? "colaborador más" : "colaboradores más")")
                .font(.caption).foregroundStyle(.primary)
        }
    }

    private var listLabel: some View {
        Label("Ver lista", systemImage: "arrow.right")
            .font(.caption.weight(.semibold)).foregroundStyle(.primary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }
}

struct AssignmentCollaboratorsView: View {
    @ObservedObject var model: AssignmentDetailViewModel
    @State private var search = ""
    @State private var selection = "Todos"

    private var categories: [String] {
        ["Todos", "Supervisión"] + Array(Set(model.collaborators.filter { !$0.es_supervisor }.map(\.cargo))).sorted()
    }

    private func matchesCategory(_ person: AssignmentCollaborator, category: String) -> Bool {
        category == "Todos" || (category == "Supervisión" ? person.es_supervisor : !person.es_supervisor && person.cargo == category)
    }

    private var filtered: [AssignmentCollaborator] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.collaborators.filter {
            matchesCategory($0, category: selection) && (query.isEmpty
                || $0.nombre.localizedStandardContains(query)
                || $0.cargo.localizedStandardContains(query)
                || ($0.es_supervisor && "Supervisor".localizedStandardContains(query)))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Buscar por nombre o cargo…", text: $search)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .foregroundStyle(.secondary).accessibilityLabel("Limpiar búsqueda")
                    }
                }
                .padding(14)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { category in
                            let count = model.collaborators.filter { matchesCategory($0, category: category) }.count
                            Button { selection = category } label: {
                                Text("\(category) (\(count))").font(.caption.weight(.medium))
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .foregroundStyle(selection == category ? Color.white : Color.primary)
                                    .background(selection == category ? Brand.red : Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(selection == category ? .isSelected : [])
                        }
                    }
                }

                if model.collaboratorsLoading && model.collaborators.isEmpty {
                    ProgressView("Cargando colaboradores…").frame(maxWidth: .infinity).padding(.top, 30)
                } else if let error = model.collaboratorsError {
                    ContentUnavailableView {
                        Label("No se pudo cargar el equipo", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Reintentar") { Task { await model.loadCollaborators() } }
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView("Sin colaboradores", systemImage: "person.2",
                        description: Text("No hay colaboradores que coincidan con la selección."))
                } else {
                    section("SUPERVISORES ASIGNADOS", people: filtered.filter(\.es_supervisor))
                    section("COLABORADORES ASIGNADOS", people: filtered.filter { !$0.es_supervisor })
                }
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Colaboradores").navigationBarTitleDisplayMode(.inline)
        .tint(Brand.red)
        .scrollDismissesKeyboard(.interactively)
        .task { await model.loadCollaborators() }
        .refreshable { await model.loadCollaborators() }
        .onChange(of: categories) { _, updated in
            if !updated.contains(selection) { selection = "Todos" }
        }
    }

    @ViewBuilder
    private func section(_ title: String, people: [AssignmentCollaborator]) -> some View {
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                LazyVStack(spacing: 12) {
                    ForEach(people) { person in
                        CollaboratorRow(person: person).padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

private struct CollaboratorRow: View {
    let person: AssignmentCollaborator

    var body: some View {
        HStack(spacing: 12) {
            CollaboratorAvatar(person: person, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { name; supervisorBadge }
                    VStack(alignment: .leading, spacing: 4) { name; supervisorBadge }
                }
                Text(person.cargo).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var name: some View { Text(person.nombre).font(.headline).fixedSize(horizontal: false, vertical: true) }

    @ViewBuilder private var supervisorBadge: some View {
        if person.es_supervisor {
            Text("Supervisor").font(.caption2.weight(.semibold)).foregroundStyle(Brand.red)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Brand.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
        }
    }
}

private struct CollaboratorAvatar: View {
    let person: AssignmentCollaborator
    let size: CGFloat

    var body: some View {
        Text(person.initials).font(size > 40 ? .headline : .caption2.bold())
            .foregroundStyle(.secondary).frame(width: size, height: size)
            .background(Color(uiColor: .quaternarySystemFill), in: Circle())
            .accessibilityHidden(true)
    }
}
