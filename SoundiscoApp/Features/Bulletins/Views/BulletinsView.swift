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
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                Text(item.asunto).font(.title.bold())
                                if let date = AgendaDate.parse(item.fecha_publicacion) {
                                    Text(date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Text(item.mensaje).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                        }.navigationTitle("Comunicado").navigationBarTitleDisplayMode(.inline)
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
