import SwiftUI

struct AssignmentNoteEditor: View {
    @ObservedObject var model: AssignmentDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var saving = false
    @State private var failure: String?
    @State private var requestID = UUID()

    var body: some View {
        NavigationStack {
            Form {
                Section("Nota / Incidencia") {
                    TextEditor(text: $content).frame(minHeight: 180).accessibilityLabel("Contenido de la nota")
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
                        saving = true
                        Task {
                            defer { saving = false }
                            do { try await model.addNote(id: requestID, content: content); dismiss() }
                            catch { failure = error.localizedDescription }
                        }
                    }.disabled(saving || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.count > 4000)
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
