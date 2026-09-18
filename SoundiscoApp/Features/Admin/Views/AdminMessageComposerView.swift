import SwiftUI

struct AdminMessageComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AdminMessageViewModel()
    @State private var asunto = ""
    @State private var cuerpo = ""
    @State private var alertMessage: String?
    @FocusState private var focused: Field?
    let onComplete: () -> Void
    private let editing: Bulletin?
    private let onSaved: ((Mensaje) -> Void)?

    init(editing: Bulletin? = nil, onSaved: ((Mensaje) -> Void)? = nil, onComplete: @escaping () -> Void) {
        self.editing = editing
        self.onSaved = onSaved
        self.onComplete = onComplete
        _asunto = State(initialValue: editing?.asunto ?? "")
        _cuerpo = State(initialValue: editing?.mensaje ?? "")
    }

    private enum Field { case asunto, cuerpo }

    var body: some View {
        Form {
            Section("Asunto del comunicado") {
                TextField("Asunto", text: $asunto)
                    .focused($focused, equals: .asunto)
            }

            Section {
                TextEditor(text: $cuerpo)
                    .frame(minHeight: 180)
                    .focused($focused, equals: .cuerpo)
                Text("\(cuerpo.count) caracteres")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } header: {
                Text("Mensaje")
            } footer: {
                Text("El comunicado será visible para toda la plantilla y no admite respuestas.")
            }

            Section {
                Button {
                    Task { await publish() }
                } label: {
                    HStack {
                        Spacer()
                        if model.isLoading { ProgressView().tint(.white) }
                        Label(model.isLoading ? "Guardando…" : editing == nil ? "Publicar comunicado" : "Guardar cambios", systemImage: "paperplane.fill")
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(!canPublish || model.isLoading)
                .listRowBackground(canPublish ? Brand.red : Color(uiColor: .tertiarySystemFill))
                .foregroundStyle(canPublish ? Color.white : Color.secondary)
            }
        }
        .disabled(model.isLoading)
        .interactiveDismissDisabled(model.isLoading)
        .navigationTitle(editing == nil ? "Crear comunicado" : "Editar comunicado")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }.disabled(model.isLoading)
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

    private var canPublish: Bool {
        !asunto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !cuerpo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
    }

    private func publish() async {
        guard canPublish, !model.isLoading else { return }
        focused = nil
        do {
            let draft = MensajeDraft(asunto: asunto, cuerpoMensaje: cuerpo)
            let saved: Mensaje
            if let editing { saved = try await model.editMessage(id: editing.id, draft: draft) }
            else { saved = try await model.publishMessage(draft) }
            onSaved?(saved)
            onComplete()
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
