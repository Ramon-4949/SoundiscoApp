import SwiftUI

struct EmployeeSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = EmployeeSelectionViewModel()
    @State private var selected: Set<UUID>
    @Binding private var confirmed: Set<UUID>
    let window: AssignmentBookingWindow
    let excluding: UUID?
    let allowsEmpty: Bool

    init(selected: Binding<Set<UUID>>, window: AssignmentBookingWindow, excluding: UUID?, allowsEmpty: Bool = false) {
        _confirmed = selected
        _selected = State(initialValue: selected.wrappedValue)
        self.window = window
        self.excluding = excluding
        self.allowsEmpty = allowsEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                searchField
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.categories, id: \.self) { category in
                            Button {
                                model.category = category
                            } label: {
                                Text(category == "Todos" ? "Todos (\(model.employees.count))" : category)
                                    .font(.subheadline.weight(model.category == category ? .semibold : .regular))
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                    .background(model.category == category ? Brand.red : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                                    .foregroundStyle(model.category == category ? .white : .primary)
                                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(model.category == category ? .isSelected : [])
                        }
                    }
                }

                if !selected.isEmpty { selectionSummary }

                VStack(alignment: .leading, spacing: 4) {
                    Text("COLABORADORES DISPONIBLES (\(model.filtered.filter(\.disponible).count))")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("\(window.start.formatted(date: .abbreviated, time: .shortened)) – \(window.end.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if model.isLoading {
                    ProgressView("Consultando disponibilidad…").frame(maxWidth: .infinity)
                } else if let error = model.errorMessage {
                    ContentUnavailableView {
                        Label("Disponibilidad no disponible", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Reintentar") { Task { await reload() } }
                    }
                } else if model.filtered.isEmpty {
                    ContentUnavailableView.search(text: model.search)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(model.filtered) { employee in
                            employeeRow(employee)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Responsables")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .tint(Brand.red)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await reload() }
        .task(id: window) { await reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reload() } }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task {
                    await reload()
                    guard canConfirmSelection else { return }
                    confirmed = selected
                    dismiss()
                }
            } label: {
                Label("Confirmar selección (\(selected.count))", systemImage: "checkmark.circle")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(canConfirmSelection ? Brand.red : Color.gray, in: RoundedRectangle(cornerRadius: 8))
            .disabled(!canConfirmSelection)
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(.bar)
        }
    }

    private var canConfirmSelection: Bool {
        model.canConfirm(selected) || (allowsEmpty && selected.isEmpty && !model.isLoading && model.errorMessage == nil)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Buscar por nombre o cargo", text: $model.search)
                .autocorrectionDisabled()
                .accessibilityLabel("Buscar colaboradores")
            if !model.search.isEmpty {
                Button { model.search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.accessibilityLabel("Borrar búsqueda")
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SELECCIONADOS PARA ESTA ASIGNACIÓN")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), alignment: .leading)], alignment: .leading) {
                selectionChips
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var selectionChips: some View {
        ForEach(selected.sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in
            let employee = model.employees.first { $0.id == id }
            Button { selected.remove(id) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle")
                    Text(employee?.displayName ?? "Empleado seleccionado").font(.subheadline)
                    if employee?.disponible == false { Image(systemName: "exclamationmark.circle") }
                    Image(systemName: "xmark.square")
                }
                .foregroundStyle(Brand.red).padding(8)
                .background(Brand.red.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(Brand.red.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quitar \(employee?.displayName ?? "empleado")")
        }
    }

    private func employeeRow(_ employee: EmployeeAvailability) -> some View {
        let isSelected = selected.contains(employee.id)
        return Button {
            if isSelected { selected.remove(employee.id) }
            else if employee.disponible { selected.insert(employee.id) }
        } label: {
            HStack(spacing: 12) {
                Text(employee.initials).font(.headline).foregroundStyle(.secondary)
                    .frame(width: 52, height: 52)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.1)))
                VStack(alignment: .leading, spacing: 6) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            Text(employee.displayName).font(.headline).foregroundStyle(.primary).fixedSize()
                            availabilityBadge(employee).fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(employee.displayName).font(.headline).foregroundStyle(.primary)
                            availabilityBadge(employee)
                        }
                    }
                    Text(employee.jobTitle).font(.subheadline).foregroundStyle(.secondary)
                    if !employee.disponible, let end = employee.ocupadoHasta {
                        Text("Ocupado hasta \(end.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : employee.disponible ? "circle" : "lock.circle")
                    .font(.title2).foregroundStyle(isSelected ? Brand.red : Color.secondary.opacity(0.5))
                    .frame(width: 30)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Brand.red : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .disabled(!employee.disponible && !isSelected)
        .accessibilityLabel("\(employee.displayName), \(employee.jobTitle), \(employee.disponible ? "disponible" : "no disponible")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func availabilityBadge(_ employee: EmployeeAvailability) -> some View {
        Text(employee.disponible ? "Disponible" : "No disponible")
            .font(.caption.weight(.semibold))
            .foregroundStyle(employee.disponible ? Color.green : Brand.red)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background((employee.disponible ? Color.green : Brand.red).opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
    }

    private func reload() async { await model.load(window: window, excluding: excluding) }
}
