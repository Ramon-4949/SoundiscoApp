import SwiftUI

struct BulletinsView: View {
    @StateObject private var model = BulletinsViewModel()
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
    }
}
