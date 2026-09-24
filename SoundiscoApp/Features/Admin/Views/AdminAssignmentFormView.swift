import SwiftUI
import UIKit

struct AdminAssignmentFormView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AdminAssignmentCRUDViewModel()
    @SceneStorage private var titulo: String
    @SceneStorage private var ubicacion: String
    @SceneStorage private var instrucciones: String
    @SceneStorage private var storedDraft: String
    @SceneStorage private var draftIsActive: Bool
    @State private var prioridad: PrioridadAsignacion = .baja
    @State private var fechaCreacion = Date()
    @State private var supervisores = Set<UUID>()
    @State private var hitos = [HitoEditorItem(fecha: Date().addingTimeInterval(3_600))]
    @State private var alertMessage: String?
    @State private var showingDiscardConfirmation = false
    @State private var validationAttempted = false
    @FocusState private var focusedField: Field?

    let tipo: TipoFlujo
    let onComplete: () -> Void
    private let editing: Asignacion?
    private let initialSnapshot: AssignmentFormSnapshot

    init(tipo: TipoFlujo, editing: Asignacion? = nil, onComplete: @escaping () -> Void) {
        self.tipo = tipo
        self.editing = editing
        self.onComplete = onComplete
        let namespace = "admin.assignment.\(editing?.id.uuidString ?? tipo.rawValue)"
        let initialTitle = editing?.titulo ?? ""
        let initialLocation = editing?.ubicacion ?? ""
        let initialInstructions = editing?.instruccionesOpcionales ?? ""
        let initialPriority = editing?.prioridad ?? .baja
        let initialDate = editing?.fechaCreacion ?? Date()
        let initialSupervisors = Set(editing?.supervisores.map(\.usuario_id) ?? [])
        let editorHitos: [HitoEditorItem]
        if let editing {
            let savedMilestones = editing.hitos.sorted { $0.orden < $1.orden }.map {
                HitoEditorItem(id: $0.id, titulo: $0.titulo, fecha: $0.fechaProgramada,
                               estado: $0.estado, notas: $0.notasIncidencias,
                               colaboradores: Set(($0.colaboradores ?? []).map(\.usuario_id)))
            }
            editorHitos = savedMilestones.isEmpty
                ? [HitoEditorItem(fecha: editing.fechaLimite ?? Date().addingTimeInterval(3_600))]
                : savedMilestones
        } else {
            editorHitos = [HitoEditorItem(fecha: Date().addingTimeInterval(3_600))]
        }
        _titulo = SceneStorage(wrappedValue: initialTitle, "\(namespace).title")
        _ubicacion = SceneStorage(wrappedValue: initialLocation, "\(namespace).location")
        _instrucciones = SceneStorage(wrappedValue: initialInstructions, "\(namespace).instructions")
        _storedDraft = SceneStorage(wrappedValue: "", "\(namespace).structuredDraft")
        _draftIsActive = SceneStorage(wrappedValue: false, "\(namespace).active")
        _prioridad = State(initialValue: initialPriority)
        _fechaCreacion = State(initialValue: initialDate)
        _supervisores = State(initialValue: initialSupervisors)
        _hitos = State(initialValue: editorHitos)
        initialSnapshot = AssignmentFormSnapshot(
            titulo: initialTitle,
            ubicacion: initialLocation,
            instrucciones: initialInstructions,
            prioridad: initialPriority,
            fechaCreacion: initialDate,
            supervisores: initialSupervisors,
            hitos: editorHitos
        )
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
                            if let window = collaboratorWindow(hito) {
                                NavigationLink {
                                    EmployeeSelectionView(selected: $hito.colaboradores, window: window, excluding: editing?.id)
                                } label: {
                                    HStack {
                                        Image(systemName: "person.2").foregroundStyle(Brand.red)
                                        Text("Colaboradores Asignados").foregroundStyle(.primary)
                                        Spacer()
                                        Text("\(hito.colaboradores.count)").foregroundStyle(.secondary)
                                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                    }.padding(.vertical, 8)
                                }.buttonStyle(.plain)
                            }
                            FieldValidationMessage(message: validationAttempted && hito.colaboradores.isEmpty
                                ? "Selecciona colaboradores para este hito." : nil)
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

            formSection("SUPERVISOR") {
                if let bookingWindow {
                    NavigationLink {
                        EmployeeSelectionView(selected: $supervisores, window: bookingWindow, excluding: editing?.id, allowsEmpty: true)
                    } label: {
                        HStack {
                            Image(systemName: "person.2").foregroundStyle(Brand.red)
                            Text("Supervisores Asignados").foregroundStyle(.primary)
                            Spacer()
                            if !supervisores.isEmpty {
                                Text("\(supervisores.count)").foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .inputSurface()
                    }
                    .buttonStyle(.plain)
                } else {
                    Label("Supervisores Asignados", systemImage: "person.2")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).inputSurface()
                }
                if bookingWindow == nil {
                    Text(itineraryError ?? "Define un período válido para consultar disponibilidad.")
                        .font(.caption).foregroundStyle(validationAttempted ? .red : .secondary)
                }
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
        .dismissKeyboardOnBackgroundTap()
        .toolbar(.hidden, for: .tabBar)
        .disabled(model.isSaving)
        .interactiveDismissDisabled(model.isSaving || hasUnsavedChanges)
        .observeInteractiveDismiss(isDisabled: model.isSaving || hasUnsavedChanges) {
            guard !model.isSaving else { return }
            requestDismiss()
        }
        .navigationTitle(editing != nil ? "Editar asignación" : "Crear Asignación")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { requestDismiss() } label: {
                    Label(editing == nil ? "Volver" : "Cerrar",
                          systemImage: editing == nil ? "chevron.left" : "xmark")
                }
                .disabled(model.isSaving)
            }
        }
        .tint(Brand.red)
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: restoreDraft)
        .onChange(of: structuredDraft) { _, draft in persist(draft) }
        .alert("No se pudo guardar", isPresented: alertBinding) {
            Button("Aceptar", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "Error desconocido")
        }
        .alert("¿Estás seguro de que quieres salir?", isPresented: $showingDiscardConfirmation) {
            Button("Continuar editando", role: .cancel) { }
            Button("Salir y descartar", role: .destructive) { discardAndDismiss() }
        } message: {
            Text("Los datos ingresados se perderán.")
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

    private func collaboratorWindow(_ item: HitoEditorItem) -> AssignmentBookingWindow? {
        guard let date = item.fecha else { return nil }
        // Administrative work reserves time from creation; field work uses the
        // selected collaborator's first-to-last milestone span on the server.
        return AssignmentBookingWindow(start: tipo == .tareaAdministrativa ? fechaCreacion : date, end: date)
    }

    private var saveTitle: String {
        if model.isSaving { return "Guardando…" }
        return editing == nil ? "Crear asignación" : "Guardar cambios"
    }

    private var canSave: Bool {
        guard rawTitleError == nil, rawLocationError == nil, rawInstructionsError == nil,
              hitos.allSatisfy({ !$0.colaboradores.isEmpty }), bookingWindow != nil else { return false }
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

    private var structuredDraft: StructuredAssignmentDraft {
        StructuredAssignmentDraft(
            prioridad: prioridad,
            fechaCreacion: fechaCreacion,
            supervisores: supervisores,
            hitos: hitos
        )
    }

    private var currentSnapshot: AssignmentFormSnapshot {
        AssignmentFormSnapshot(
            titulo: titulo,
            ubicacion: ubicacion,
            instrucciones: instrucciones,
            prioridad: prioridad,
            fechaCreacion: fechaCreacion,
            supervisores: supervisores,
            hitos: hitos
        )
    }

    private var hasUnsavedChanges: Bool {
        draftIsActive && currentSnapshot != initialSnapshot
    }

    private func canDelete(_ hito: HitoEditorItem) -> Bool {
        hitos.count > 1 && hito.estado != .completado
    }

    private func restoreDraft() {
        guard draftIsActive else {
            apply(initialSnapshot)
            storedDraft = ""
            draftIsActive = true
            return
        }
        guard let data = storedDraft.data(using: .utf8),
              let restored = try? JSONDecoder().decode(StructuredAssignmentDraft.self, from: data) else { return }
        prioridad = restored.prioridad
        fechaCreacion = restored.fechaCreacion
        supervisores = restored.supervisores
        hitos = restored.hitos
    }

    private func persist(_ draft: StructuredAssignmentDraft) {
        guard draftIsActive,
              let data = try? JSONEncoder().encode(draft),
              let encoded = String(data: data, encoding: .utf8) else { return }
        storedDraft = encoded
    }

    private func requestDismiss() {
        focusedField = nil
        if hasUnsavedChanges {
            showingDiscardConfirmation = true
        } else {
            clearPersistedDraft()
            dismiss()
        }
    }

    private func discardAndDismiss() {
        apply(initialSnapshot)
        clearPersistedDraft()
        dismiss()
    }

    private func apply(_ snapshot: AssignmentFormSnapshot) {
        titulo = snapshot.titulo
        ubicacion = snapshot.ubicacion
        instrucciones = snapshot.instrucciones
        prioridad = snapshot.prioridad
        fechaCreacion = snapshot.fechaCreacion
        supervisores = snapshot.supervisores
        hitos = snapshot.hitos
    }

    private func clearPersistedDraft() {
        storedDraft = ""
        draftIsActive = false
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
                    notasIncidencias: item.notas,
                    colaboradoresIDs: Array(item.colaboradores)
                )
            }
        var draft = AsignacionDraft(
            tipoFlujo: tipo,
            titulo: titulo,
            ubicacion: tipo == .operacionesCampo ? ubicacion : nil,
            prioridad: prioridad,
            instruccionesOpcionales: instrucciones.nilIfBlank,
            estado: editing?.estado ?? .pendiente,
            empleadosIDs: Array(Set(hitos.flatMap { $0.colaboradores })),
            fechaCreacion: fechaCreacion,
            fechaLimite: tipo == .tareaAdministrativa ? itinerary.last?.fechaProgramada : nil,
            hitos: itinerary
        )
        draft.supervisoresIDs = Array(supervisores)
        do {
            if let editing {
                _ = try await model.updateAssignment(id: editing.id, with: draft)
            } else {
                _ = try await model.createAssignment(draft)
            }
            clearPersistedDraft()
            onComplete()
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

private struct HitoEditorItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var titulo = ""
    var fecha: Date?
    var estado: EstadoHito = .bloqueado
    var notas: String?
    var colaboradores = Set<UUID>()
}

private struct StructuredAssignmentDraft: Codable, Equatable {
    var prioridad: PrioridadAsignacion
    var fechaCreacion: Date
    var supervisores: Set<UUID>
    var hitos: [HitoEditorItem]
}

private struct AssignmentFormSnapshot: Equatable {
    var titulo: String
    var ubicacion: String
    var instrucciones: String
    var prioridad: PrioridadAsignacion
    var fechaCreacion: Date
    var supervisores: Set<UUID>
    var hitos: [HitoEditorItem]
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

    func dismissKeyboardOnBackgroundTap() -> some View {
        modifier(BackgroundKeyboardDismissModifier())
    }

    func observeInteractiveDismiss(isDisabled: Bool, onAttempt: @escaping () -> Void) -> some View {
        background(InteractiveDismissObserver(isDisabled: isDisabled, onAttempt: onAttempt))
    }
}

private struct BackgroundKeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }
}

private struct InteractiveDismissObserver: UIViewControllerRepresentable {
    let isDisabled: Bool
    let onAttempt: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onAttempt: onAttempt) }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.isDisabled = isDisabled
        context.coordinator.onAttempt = onAttempt
        DispatchQueue.main.async {
            var hostingController = controller
            while let parent = hostingController.parent { hostingController = parent }
            hostingController.presentationController?.delegate = context.coordinator
            hostingController.isModalInPresentation = isDisabled
        }
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var isDisabled: Bool
        var onAttempt: () -> Void

        init(isDisabled: Bool = false, onAttempt: @escaping () -> Void) {
            self.isDisabled = isDisabled
            self.onAttempt = onAttempt
        }

        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            !isDisabled
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            guard isDisabled else { return }
            onAttempt()
        }
    }
}

private extension PrioridadAsignacion {
    var label: String { rawValue.capitalized }
}
