import SwiftUI

struct BulletinDetailView: View {
    @Environment(\.isAdministrator) private var isAdministrator
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AdminMessageViewModel()
    @State private var bulletin: Bulletin
    @State private var editor: Bulletin?
    @State private var confirmDelete = false
    @State private var failure: String?

    init(bulletin: Bulletin) { _bulletin = State(initialValue: bulletin) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ASUNTO DEL COMUNICADO")
                        .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "megaphone.fill")
                            .foregroundStyle(Brand.red).accessibilityHidden(true)
                        Text(bulletin.asunto).font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let date = AgendaDate.parse(bulletin.fecha_publicacion) {
                        Label(date.formatted(date: .long, time: .shortened), systemImage: "calendar")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .bulletinSurface()

                VStack(alignment: .leading, spacing: 12) {
                    Text("MENSAJE")
                        .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(bulletin.mensaje)
                        .font(.body).lineSpacing(5).textSelection(.enabled)
                }
                .bulletinSurface()

                Label("Comunicado de solo lectura", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Detalle del comunicado")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Brand.red)
        .toolbar {
            if isAdministrator {
                Menu {
                    Button("Editar", systemImage: "pencil") { editor = bulletin }
                    Button("Eliminar", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: { Label("Administrar comunicado", systemImage: "ellipsis.circle") }
                .disabled(model.isLoading)
            }
        }
        .sheet(item: $editor) { item in
            NavigationStack {
                AdminMessageComposerView(editing: item, onSaved: { saved in
                    bulletin = Bulletin(id: saved.id, asunto: saved.asunto, mensaje: saved.cuerpoMensaje,
                                        fecha_publicacion: ISO8601DateFormatter().string(from: saved.fechaEnvio))
                }, onComplete: {})
            }
        }
        .confirmationDialog("¿Eliminar este comunicado?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Eliminar comunicado", role: .destructive) {
                Task {
                    do {
                        try await model.deleteMessage(id: bulletin.id)
                        dismiss()
                    } catch { failure = error.localizedDescription }
                }
            }
        } message: { Text("Dejará de estar disponible para toda la plantilla. Esta acción no se puede deshacer.") }
        .alert("No se pudo eliminar", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("Aceptar", role: .cancel) { failure = nil }
        } message: { Text(failure ?? "") }
    }
}

private extension View {
    func bulletinSurface() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
