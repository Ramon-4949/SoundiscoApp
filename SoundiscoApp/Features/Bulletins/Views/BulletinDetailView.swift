import SwiftUI

struct BulletinDetailView: View {
    let bulletin: Bulletin

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
    }
}

private extension View {
    func bulletinSurface() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
