import SwiftUI

struct AssignmentNoteEditor: View {
    @ObservedObject var model: AssignmentDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var saving = false
    @State private var failure: String?
    @State private var requestID = UUID()
    @State private var validationAttempted = false

    private var rawContentError: String? {
        FormValidation.text(content, field: "La nota", minimum: 3, maximum: 4000)
    }

    private var contentError: String? { validationAttempted ? rawContentError : nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nota / Incidencia") {
                    TextEditor(text: $content)
                        .frame(minHeight: 180)
                        .padding(6)
                        .validationBorder(contentError)
                        .accessibilityLabel("Contenido de la nota")
                    FieldValidationMessage(message: contentError)
                    Text("\(content.count) / 4000").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Añadir nota").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publicar") {
                        validationAttempted = true
                        guard rawContentError == nil else { return }
                        saving = true
                        Task {
                            defer { saving = false }
                            do { try await model.addNote(id: requestID, content: content); dismiss() }
                            catch { failure = error.localizedDescription }
                        }
                    }.disabled(saving)
                }
            }
            .disabled(saving).overlay { if saving { ProgressView() } }
            .interactiveDismissDisabled(saving)
            .alert("No se pudo publicar", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("Aceptar", role: .cancel) {}
            } message: { Text(failure ?? "") }
        }.tint(Brand.red)
    }
}
