import SwiftUI

struct BulletinsView: View {
    @Environment(\.isAdministrator) private var isAdministrator
    @StateObject private var model = BulletinsViewModel()
    @State private var creating = false
    var body: some View {
        List {
            if model.loading { ProgressView("Cargando comunicados…") }
            else if let failure = model.failure {
                Text(failure).foregroundStyle(.secondary)
                Button("Reintentar") { Task { await model.load() } }
            } else if model.items.isEmpty {
                ContentUnavailableView("Sin comunicados", systemImage: "megaphone", description: Text("Los avisos de SounDisco aparecerán aquí."))
            } else {
                ForEach(model.items) { item in
                    NavigationLink {
                        BulletinDetailView(bulletin: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.asunto).font(.headline)
                            Text(item.mensaje).lineLimit(2).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                }
            }
        }
        .navigationTitle("Comunicados").task { await model.load() }.refreshable { await model.load() }
        .toolbar {
            if isAdministrator {
                Button { creating = true } label: { Label("Crear comunicado", systemImage: "square.and.pencil") }
            }
        }
        .sheet(isPresented: $creating, onDismiss: { Task { await model.load() } }) {
            NavigationStack { AdminMessageComposerView(onComplete: {}) }
        }
    }
}
