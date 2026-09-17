import SwiftUI

struct AdminAssignmentMenu: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AdminAssignmentCRUDViewModel()
    @State private var editing: Asignacion?
    @State private var loading = false
    @State private var confirmDelete = false
    @State private var failure: String?
    let assignmentID: UUID
    let onChanged: () -> Void

    var body: some View {
        Menu {
            Button("Editar", systemImage: "pencil") {
                loading = true
                Task {
                    defer { loading = false }
                    do { editing = try await model.fetchAssignment(id: assignmentID) }
                    catch { failure = error.localizedDescription }
                }
            }
            Button("Eliminar", systemImage: "trash", role: .destructive) { confirmDelete = true }
        } label: {
            if loading || model.isSaving { ProgressView() }
            else { Label("Administrar asignación", systemImage: "ellipsis.circle") }
        }
        .disabled(loading || model.isSaving)
        .sheet(item: $editing) { item in
            NavigationStack {
                AdminAssignmentFormView(tipo: item.tipoFlujo, editing: item, onComplete: onChanged)
            }
        }
        .confirmationDialog("¿Eliminar esta asignación?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Eliminar asignación", role: .destructive) {
                Task {
                    do {
                        try await model.deleteAssignment(id: assignmentID)
                        dismiss()
                    } catch { failure = error.localizedDescription }
                }
            }
        } message: {
            Text("Se eliminarán también su itinerario, equipo y checklist de equipos. Esta acción no se puede deshacer.")
        }
        .alert("No se pudo completar", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("Aceptar", role: .cancel) { failure = nil }
        } message: { Text(failure ?? "") }
    }
}
