import SwiftUI

struct AdminAssignmentFormView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AdminAssignmentCRUDViewModel()
    @State private var titulo = ""
    @State private var ubicacion = ""
    @State private var prioridad: PrioridadAsignacion = .media
    @State private var instrucciones = ""
    @State private var fechaLimite = Date().addingTimeInterval(86_400)
    @State private var responsables = Set<UUID>()
    @State private var hitos = [HitoEditorItem(fecha: Date().addingTimeInterval(3_600))]
    @State private var alertMessage: String?
    @FocusState private var focusedField: Field?

    let tipo: TipoFlujo
    let onComplete: () -> Void
    private let editing: Asignacion?

    init(tipo: TipoFlujo, editing: Asignacion? = nil, onComplete: @escaping () -> Void) {
        self.tipo = tipo
        self.editing = editing
        self.onComplete = onComplete
        if let editing {
            _titulo = State(initialValue: editing.titulo)
            _ubicacion = State(initialValue: editing.ubicacion ?? "")
            _prioridad = State(initialValue: editing.prioridad)
            _instrucciones = State(initialValue: editing.instruccionesOpcionales ?? "")
            _fechaLimite = State(initialValue: editing.fechaLimite ?? .now)
            _responsables = State(initialValue: Set(editing.asignadoA.map(\.id)))
            _hitos = State(initialValue: editing.hitos.sorted { $0.orden < $1.orden }.map {
                HitoEditorItem(id: $0.id, titulo: $0.titulo, fecha: $0.fechaProgramada,
                               estado: $0.estado, notas: $0.notasIncidencias)
            })
        }
    }

    private enum Field: Hashable { case titulo, ubicacion, instrucciones }

    var body: some View {
        Form {
            Section("Asignación") {
                TextField("Título", text: $titulo)
                    .focused($focusedField, equals: .titulo)
                if tipo == .operacionesCampo {
                    TextField("Ubicación del evento", text: $ubicacion)
                        .focused($focusedField, equals: .ubicacion)
                } else {
                    DatePicker(
                        "Fecha límite",
                        selection: $fechaLimite,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }

            if tipo == .operacionesCampo {
                Section {
                    ForEach($hitos) { $hito in
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Nombre del hito", text: $hito.titulo)
                            DatePicker(
                                "Fecha y hora",
                                selection: Binding(get: { hito.fecha ?? .now }, set: { hito.fecha = $0 }),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            if hito.fecha == nil {
                                Text("Selecciona la fecha del hito").font(.caption).foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { if !hasProgress { hitos.remove(atOffsets: $0) } }
                    .onMove { if !hasProgress { hitos.move(fromOffsets: $0, toOffset: $1) } }

                    Button {
                        hitos.append(HitoEditorItem(fecha: suggestedMilestoneDate))
                    } label: {
                        Label("Añadir hito", systemImage: "plus.circle.fill")
                    }
                    .disabled(hasProgress)
                } header: {
                    Text("Itinerario")
                } footer: {
                    Text("Los técnicos completarán los hitos en este mismo orden.")
                }
            }

            Section("Responsables") {
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                    Button("Reintentar") { Task { await model.loadEmployees() } }
                }
                if model.isLoadingEmployees {
                    ProgressView("Cargando empleados…")
                } else if availableEmployees.isEmpty {
                    ContentUnavailableView(
                        "Sin empleados disponibles",
                        systemImage: "person.2.slash",
                        description: Text(employeeEmptyMessage)
                    )
                } else {
                    ForEach(availableEmployees) { employee in
                        Button {
                            toggle(employee.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(employee.nombre ?? "Empleado sin nombre")
                                    Text(employee.rol?.label ?? "Rol sin definir")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: responsables.contains(employee.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(responsables.contains(employee.id) ? Brand.red : .secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(employee.nombre ?? "Empleado"), \(responsables.contains(employee.id) ? "seleccionado" : "no seleccionado")")
                    }
                }
            }

            Section("Prioridad") {
                Picker("Nivel", selection: $prioridad) {
                    ForEach(PrioridadAsignacion.allCases, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Instrucciones opcionales") {
                TextField("Indicaciones para el equipo", text: $instrucciones, axis: .vertical)
                    .lineLimit(3...7)
                    .focused($focusedField, equals: .instrucciones)
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if model.isSaving { ProgressView().tint(.white) }
                        Text(saveTitle)
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(!canSave || model.isSaving)
                .listRowBackground(canSave ? Color(red: 0.76, green: 0, blue: 0.09) : Color(uiColor: .tertiarySystemFill))
                .foregroundStyle(canSave ? Color.white : Color.secondary)
            }
        }
        .disabled(model.isSaving)
        .interactiveDismissDisabled(model.isSaving)
        .navigationTitle(editing != nil ? "Editar asignación" : tipo == .operacionesCampo ? "Operación de campo" : "Tarea administrativa")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if tipo == .operacionesCampo && !hasProgress {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            if editing != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.disabled(model.isSaving)
                }
            }
        }
        .tint(Brand.red)
        .scrollDismissesKeyboard(.interactively)
        .task { await model.loadEmployees() }
        .alert("No se pudo guardar", isPresented: alertBinding) {
            Button("Aceptar", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "Error desconocido")
        }
    }

    private var availableEmployees: [Empleado] {
        model.empleados
    }

    private var saveTitle: String {
        if model.isSaving { return "Guardando…" }
        return editing == nil ? "Crear asignación" : "Guardar cambios"
    }

    private var employeeEmptyMessage: String {
        "No hay perfiles de empleados disponibles."
    }

    private var canSave: Bool {
        guard !titulo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !responsables.isEmpty else { return false }
        if tipo == .operacionesCampo {
            return !ubicacion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !hitos.isEmpty && hitos.allSatisfy { $0.fecha != nil && !$0.titulo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        return true
    }

    private var suggestedMilestoneDate: Date {
        (hitos.last?.fecha ?? .now).addingTimeInterval(3_600)
    }

    private var hasProgress: Bool { editing?.hitos.contains { $0.estado == .completado } == true }

    private var alertBinding: Binding<Bool> {
        Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
    }

    private func toggle(_ id: UUID) {
        if responsables.contains(id) { responsables.remove(id) } else { responsables.insert(id) }
    }

    private func save() async {
        guard canSave, !model.isSaving else { return }
        focusedField = nil
        let itinerary = tipo == .operacionesCampo
            ? hitos.enumerated().map { index, item in
                HitoDraft(
                    id: item.id,
                    orden: index + 1,
                    titulo: item.titulo,
                    fechaProgramada: item.fecha!,
                    estado: hasProgress ? item.estado : index == 0 ? .enCurso : .bloqueado,
                    notasIncidencias: item.notas
                )
            }
            : []
        let draft = AsignacionDraft(
            tipoFlujo: tipo,
            titulo: titulo,
            ubicacion: tipo == .operacionesCampo ? ubicacion : nil,
            prioridad: prioridad,
            instruccionesOpcionales: instrucciones.nilIfBlank,
            estado: editing?.estado ?? .pendiente,
            empleadosIDs: Array(responsables),
            fechaCreacion: editing?.fechaCreacion ?? .now,
            fechaLimite: tipo == .tareaAdministrativa ? fechaLimite : nil,
            hitos: itinerary
        )
        do {
            if let editing {
                _ = try await model.updateAssignment(id: editing.id, with: draft)
            } else {
                _ = try await model.createAssignment(draft)
            }
            onComplete()
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

private struct HitoEditorItem: Identifiable {
    var id = UUID()
    var titulo = ""
    var fecha: Date?
    var estado: EstadoHito = .bloqueado
    var notas: String?
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension RolEmpleado {
    var label: String { self == .admin ? "Administración" : "Técnico" }
}

private extension PrioridadAsignacion {
    var label: String { rawValue.capitalized }
}
