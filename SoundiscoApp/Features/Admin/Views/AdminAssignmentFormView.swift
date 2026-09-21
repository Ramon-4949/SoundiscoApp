import SwiftUI

struct AdminAssignmentFormView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AdminAssignmentCRUDViewModel()
    @State private var titulo = ""
    @State private var ubicacion = ""
    @State private var prioridad: PrioridadAsignacion = .baja
    @State private var instrucciones = ""
    @State private var fechaCreacion = Date()
    @State private var responsables = Set<UUID>()
    @State private var hitos = [HitoEditorItem(fecha: Date().addingTimeInterval(3_600))]
    @State private var alertMessage: String?
    @State private var validationAttempted = false
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
            _fechaCreacion = State(initialValue: editing.fechaCreacion)
            _responsables = State(initialValue: Set(editing.asignadoA.map(\.id)))
            let editorHitos = editing.hitos.sorted { $0.orden < $1.orden }.map {
                HitoEditorItem(id: $0.id, titulo: $0.titulo, fecha: $0.fechaProgramada,
                               estado: $0.estado, notas: $0.notasIncidencias)
            }
            _hitos = State(initialValue: editorHitos.isEmpty
                ? [HitoEditorItem(fecha: editing.fechaLimite ?? Date().addingTimeInterval(3_600))]
                : editorHitos)
        }
    }

    private enum Field: Hashable { case titulo, ubicacion, instrucciones }

    var body: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 28) {
            formSection("TÍTULO DE LA ASIGNACIÓN") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text").foregroundStyle(Brand.red)
                        TextField("Ej. Montaje de Sonido Principal", text: $titulo)
                            .focused($focusedField, equals: .titulo)
                    }.inputSurface(error: titleError)
                    FieldValidationMessage(message: titleError)
                }
            }
                if tipo == .operacionesCampo {
                    formSection("UBICACIÓN DEL EVENTO") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.and.ellipse").foregroundStyle(Brand.red)
                                TextField("Ej. Auditorio Central - Piso 2", text: $ubicacion)
                                    .focused($focusedField, equals: .ubicacion)
                            }.inputSurface(error: locationError)
                            FieldValidationMessage(message: locationError)
                        }
                    }
                }

            formSection("ITINERARIO Y LOGÍSTICA DE TIEMPOS") {
                    ForEach($hitos) { $hito in
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "pencil").foregroundStyle(.secondary)
                                TextField("Salida en ruta", text: $hito.titulo)
                                if canDelete(hito) {
                                    Button {
                                        hitos.removeAll { $0.id == hito.id }
                                    } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }
                                    .accessibilityLabel("Eliminar hito")
                                }
                            }
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 16) {
                                    milestoneDate($hito, components: .date, title: "FECHA", icon: "calendar")
                                    milestoneDate($hito, components: .hourAndMinute, title: "HORARIO", icon: "clock")
                                }
                                VStack(alignment: .leading, spacing: 12) {
                                    milestoneDate($hito, components: .date, title: "FECHA", icon: "calendar")
                                    milestoneDate($hito, components: .hourAndMinute, title: "HORARIO", icon: "clock")
                                }
                            }
                            if hito.fecha == nil {
                                Text("Selecciona la fecha del hito").font(.caption).foregroundStyle(.red)
                            }
                        }
                        .inputSurface(error: milestoneTitleError(hito))
                        .contextMenu {
                            if !hasProgress {
                                Button("Mover arriba", systemImage: "arrow.up") { moveHito(hito.id, direction: -1) }
                                Button("Mover abajo", systemImage: "arrow.down") { moveHito(hito.id, direction: 1) }
                            }
                        }
                        FieldValidationMessage(message: milestoneTitleError(hito))
                    }

                    FieldValidationMessage(message: itineraryError)

                    Button {
                        hitos.append(HitoEditorItem(fecha: suggestedMilestoneDate))
                    } label: {
                        Label("Añadir Hito / Horario", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(Brand.red.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Brand.red.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    }
                    .buttonStyle(.plain).foregroundStyle(Brand.red)
            }

            formSection("ASIGNAR RESPONSABLES") {
                if let bookingWindow {
                    NavigationLink {
                        EmployeeSelectionView(selected: $responsables, window: bookingWindow, excluding: editing?.id)
                    } label: {
                        HStack {
                            Image(systemName: "person.2").foregroundStyle(Brand.red)
                            Text("Responsables Asignados").foregroundStyle(.primary)
                            Spacer()
                            if !responsables.isEmpty {
                                Text("\(responsables.count)").foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .inputSurface(error: responsibleError)
                    }
                    .buttonStyle(.plain)
                } else {
                    Label("Responsables Asignados", systemImage: "person.2")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).inputSurface()
                }
                if bookingWindow == nil {
                    Text(itineraryError ?? "Define un período válido para consultar disponibilidad.")
                        .font(.caption).foregroundStyle(validationAttempted ? .red : .secondary)
                }
                FieldValidationMessage(message: responsibleError)
            }

            formSection("NIVEL DE PRIORIDAD") {
                Picker("Nivel", selection: $prioridad) {
                    ForEach(PrioridadAsignacion.allCases, id: \.self) {
                        Label($0.label, systemImage: "flag.fill").tag($0)
                    }
                }
                .pickerStyle(.segmented)
            }

            formSection("INSTRUCCIONES LOGÍSTICAS (OPCIONAL)") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "text.bubble").foregroundStyle(Brand.red)
                        TextField("Ej. Revisar balance de cableado multipar y consolas auxiliares.", text: $instrucciones, axis: .vertical)
                            .lineLimit(3...7)
                            .focused($focusedField, equals: .instrucciones)
                    }.inputSurface(error: instructionsError)
                    HStack {
                        FieldValidationMessage(message: instructionsError)
                        Spacer()
                        Text("\(instrucciones.count) / 2000").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if model.isSaving { ProgressView().tint(.white) }
                        Label(saveTitle, systemImage: "checkmark.circle")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.vertical, 18)
                    .background(Brand.red, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(model.isSaving)
                .foregroundStyle(.white)
          }.padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar(.hidden, for: .tabBar)
        .disabled(model.isSaving)
        .interactiveDismissDisabled(model.isSaving)
        .navigationTitle(editing != nil ? "Editar asignación" : "Crear Asignación")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editing != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.disabled(model.isSaving)
                }
            }
        }
        .tint(Brand.red)
        .scrollDismissesKeyboard(.interactively)
        .alert("No se pudo guardar", isPresented: alertBinding) {
            Button("Aceptar", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "Error desconocido")
        }
    }

    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content()
        }
    }

    private func milestoneDate(_ hito: Binding<HitoEditorItem>, components: DatePickerComponents, title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(Brand.red)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                DatePicker(title, selection: Binding(get: { hito.wrappedValue.fecha ?? .now },
                    set: { hito.wrappedValue.fecha = $0 }), displayedComponents: components)
                    .labelsHidden().fixedSize()
            }
        }
    }

    private func moveHito(_ id: UUID, direction: Int) {
        guard let index = hitos.firstIndex(where: { $0.id == id }), hitos.indices.contains(index + direction) else { return }
        hitos.swapAt(index, index + direction)
    }

    private var bookingWindow: AssignmentBookingWindow? {
        if tipo == .tareaAdministrativa {
            let dates = hitos.compactMap(\.fecha)
            guard dates.count == hitos.count, let end = dates.last,
                  end >= fechaCreacion,
                  zip(dates, dates.dropFirst()).allSatisfy({ $0 <= $1 }) else { return nil }
            return AssignmentBookingWindow(start: fechaCreacion, end: end)
        }
        let dates = hitos.compactMap(\.fecha)
        guard dates.count == hitos.count, let start = dates.first, let end = dates.last,
              zip(dates, dates.dropFirst()).allSatisfy({ $0 <= $1 }) else { return nil }
        return AssignmentBookingWindow(start: start, end: end)
    }

    private var saveTitle: String {
        if model.isSaving { return "Guardando…" }
        return editing == nil ? "Crear asignación" : "Guardar cambios"
    }

    private var canSave: Bool {
        guard rawTitleError == nil, rawLocationError == nil, rawInstructionsError == nil,
              !responsables.isEmpty, bookingWindow != nil else { return false }
        guard validMilestones else { return false }
        if tipo == .operacionesCampo {
            return !ubicacion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return hitos.allSatisfy {
            guard let date = $0.fecha else { return false }
            return date >= fechaCreacion
        }
    }

    private var suggestedMilestoneDate: Date {
        (hitos.last?.fecha ?? .now).addingTimeInterval(3_600)
    }

    private var validMilestones: Bool {
        let dates = hitos.compactMap(\.fecha)
        return !hitos.isEmpty && dates.count == hitos.count &&
            hitos.allSatisfy { FormValidation.text($0.titulo, field: "El título del hito", minimum: 2, maximum: 100) == nil } &&
            zip(dates, dates.dropFirst()).allSatisfy { $0 <= $1 }
    }

    private var rawTitleError: String? {
        FormValidation.text(titulo, field: "El título", minimum: 3, maximum: 120)
    }

    private var rawLocationError: String? {
        guard tipo == .operacionesCampo else { return nil }
        return FormValidation.text(ubicacion, field: "La ubicación", minimum: 3, maximum: 180)
    }

    private var rawInstructionsError: String? {
        FormValidation.text(instrucciones, field: "Las instrucciones", minimum: 1, maximum: 2000, required: false)
    }

    private var titleError: String? { validationAttempted ? rawTitleError : nil }
    private var locationError: String? { validationAttempted ? rawLocationError : nil }
    private var instructionsError: String? { validationAttempted ? rawInstructionsError : nil }
    private var responsibleError: String? {
        validationAttempted && responsables.isEmpty ? "Selecciona al menos un responsable disponible." : nil
    }

    private func milestoneTitleError(_ item: HitoEditorItem) -> String? {
        guard validationAttempted else { return nil }
        return FormValidation.text(item.titulo, field: "El título del hito", minimum: 2, maximum: 100)
    }

    private var itineraryError: String? {
        guard validationAttempted else { return nil }
        guard !hitos.isEmpty else { return "Añade al menos un hito." }
        let dates = hitos.compactMap(\.fecha)
        guard dates.count == hitos.count else { return "Todos los hitos necesitan fecha y hora." }
        guard zip(dates, dates.dropFirst()).allSatisfy({ $0 <= $1 }) else {
            return "Las fechas de los hitos deben mantener el orden del itinerario."
        }
        if tipo == .tareaAdministrativa, dates.contains(where: { $0 < fechaCreacion }) {
            return "Los hitos administrativos no pueden ser anteriores a la creación de la asignación."
        }
        return nil
    }

    private var hasProgress: Bool { editing?.hitos.contains { $0.estado == .completado } == true }

    private func canDelete(_ hito: HitoEditorItem) -> Bool {
        hitos.count > 1 && hito.estado != .completado
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
    }

    private func save() async {
        validationAttempted = true
        guard canSave, !model.isSaving else {
            if rawTitleError != nil { focusedField = .titulo }
            else if rawLocationError != nil { focusedField = .ubicacion }
            else if rawInstructionsError != nil { focusedField = .instrucciones }
            return
        }
        focusedField = nil
        let itinerary = hitos.enumerated().map { index, item in
                HitoDraft(
                    id: item.id,
                    orden: index + 1,
                    titulo: item.titulo,
                    fechaProgramada: item.fecha!,
                    estado: hasProgress ? item.estado : index == 0 ? .enCurso : .bloqueado,
                    notasIncidencias: item.notas
                )
            }
        let draft = AsignacionDraft(
            tipoFlujo: tipo,
            titulo: titulo,
            ubicacion: tipo == .operacionesCampo ? ubicacion : nil,
            prioridad: prioridad,
            instruccionesOpcionales: instrucciones.nilIfBlank,
            estado: editing?.estado ?? .pendiente,
            empleadosIDs: Array(responsables),
            fechaCreacion: fechaCreacion,
            fechaLimite: tipo == .tareaAdministrativa ? itinerary.last?.fechaProgramada : nil,
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

private extension View {
    func inputSurface(error: String? = nil) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            .validationBorder(error)
    }
}

private extension PrioridadAsignacion {
    var label: String { rawValue.capitalized }
}
