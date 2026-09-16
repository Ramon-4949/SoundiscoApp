import SwiftUI

struct AdminCreationTypeView: View {
    let onComplete: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("¿Qué deseas crear?")
                        .font(.largeTitle.bold())
                    Text("Selecciona el flujo. Cada formulario mostrará únicamente los datos necesarios.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section {
                creationLink(
                    title: "Operaciones de campo",
                    subtitle: "Logística, montaje y trabajo en ubicaciones externas.",
                    eyebrow: "FLUJO OPERATIVO",
                    symbol: "truck.box"
                ) {
                    AdminAssignmentFormView(tipo: .operacionesCampo, onComplete: onComplete)
                }

                creationLink(
                    title: "Tareas administrativas",
                    subtitle: "Reportes, auditorías y trabajo interno con fecha límite.",
                    eyebrow: "GESTIÓN CORPORATIVA",
                    symbol: "doc.text"
                ) {
                    AdminAssignmentFormView(tipo: .tareaAdministrativa, onComplete: onComplete)
                }

                creationLink(
                    title: "Comunicado",
                    subtitle: "Avisos e itinerarios enviados a toda la plantilla.",
                    eyebrow: "COMUNICACIONES",
                    symbol: "megaphone"
                ) {
                    AdminMessageComposerView(onComplete: onComplete)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Crear")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Brand.red)
    }

    private func creationLink<Destination: View>(
        title: String,
        subtitle: String,
        eyebrow: String,
        symbol: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(Brand.red)
                    .frame(width: 44, height: 44)
                    .background(Brand.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow).font(.caption.weight(.semibold)).foregroundStyle(Brand.red)
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 8)
        }
    }
}
