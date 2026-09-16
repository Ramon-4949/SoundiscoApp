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
                                selection: $hito.fecha,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { hitos.remove(atOffsets: $0) }
                    .onMove { hitos.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        hitos.append(HitoEditorItem(fecha: suggestedMilestoneDate))
                    } label: {
                        Label("Añadir hito", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Itinerario")
                } footer: {
                    Text("Los técnicos completarán los hitos en este mismo orden.")
                }
            }

            Section("Responsables") {
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
                        Text(model.isSaving ? "Guardando…" : "Crear asignación")
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(!canSave || model.isSaving)
                .listRowBackground(canSave ? Color(red: 0.76, green: 0, blue: 0.09) : Color(uiColor: .tertiarySystemFill))
                .foregroundStyle(canSave ? Color.white : Color.secondary)
            }
        }
        .navigationTitle(tipo == .operacionesCampo ? "Operación de campo" : "Tarea administrativa")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if tipo == .operacionesCampo { EditButton() } }
        .tint(Brand.red)
        .scrollDismissesKeyboard(.interactively)
        .task { await model.loadEmployees() }
        .alert("No se pudo crear", isPresented: alertBinding) {
            Button("Aceptar", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "Error desconocido")
        }
    }

    private var availableEmployees: [Empleado] {
        model.empleados.filter { employee in
            switch tipo {
            case .operacionesCampo: employee.rol == .tecnico
            case .tareaAdministrativa: employee.rol == .admin
            }
        }
    }

    private var employeeEmptyMessage: String {
        tipo == .operacionesCampo
            ? "No hay perfiles con rol técnico."
            : "No hay perfiles con rol administrador."
    }

    private var canSave: Bool {
        guard !titulo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !responsables.isEmpty else { return false }
        if tipo == .operacionesCampo {
            return !ubicacion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !hitos.isEmpty && hitos.allSatisfy { !$0.titulo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        return true
    }

    private var suggestedMilestoneDate: Date {
        (hitos.last?.fecha ?? .now).addingTimeInterval(3_600)
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
    }

    private func toggle(_ id: UUID) {
        if responsables.contains(id) { responsables.remove(id) } else { responsables.insert(id) }
    }

    private func save() async {
        focusedField = nil
        let itinerary = tipo == .operacionesCampo
            ? hitos.enumerated().map { index, item in
                HitoDraft(
                    orden: index + 1,
                    titulo: item.titulo,
                    fechaProgramada: item.fecha,
                    estado: index == 0 ? .enCurso : .bloqueado
                )
            }
            : []
        let draft = AsignacionDraft(
            tipoFlujo: tipo,
            titulo: titulo,
            ubicacion: tipo == .operacionesCampo ? ubicacion : nil,
            prioridad: prioridad,
            instruccionesOpcionales: instrucciones.nilIfBlank,
            empleadosIDs: Array(responsables),
            fechaLimite: tipo == .tareaAdministrativa ? fechaLimite : nil,
            hitos: itinerary
        )
        do {
            _ = try await model.createAssignment(draft)
            onComplete()
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

private struct HitoEditorItem: Identifiable {
    let id = UUID()
    var titulo = ""
    var fecha: Date
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
