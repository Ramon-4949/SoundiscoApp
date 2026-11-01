import SwiftUI

struct SupportView: View {
    var body: some View {
        Form {
            Section("Contacto") {
                Text("SOUND DISCO FR EIRL").font(.headline)
                Link(destination: URL(string: "mailto:soundiscomedia@gmail.com?subject=Soporte%20SounDisco")!) {
                    Label("soundiscomedia@gmail.com", systemImage: "envelope")
                }
                .textSelection(.enabled)
                Text("Escríbenos para recibir asistencia con tu cuenta, reportar contenido inapropiado o solicitar una revisión de tus datos.")
                Text("Indica la fecha, la asignación o el hito afectado y el mensaje de error. Nunca compartas tu contraseña ni los códigos de verificación.")
                    .foregroundStyle(.secondary)
            }
            Section("Privacidad y cuenta") {
                Link(destination: URL(string: "https://soundisco-privacidad-soporte.soundiscomedia.chatgpt.site/soporte/")!) {
                    Label("Centro de soporte en la web", systemImage: "arrow.up.right.square")
                }
                NavigationLink("Política de privacidad") { LegalDocumentView(document: .privacy) }
                NavigationLink("Términos de servicio") { LegalDocumentView(document: .terms) }
                Text("Puedes iniciar la eliminación de tu cuenta desde Mi perfil, incluso si tu acceso está pendiente de aprobación.")
            }
            Section("Versión") {
                LabeledContent("SounDisco", value: version)
            }
        }
        .navigationTitle("Ayuda y soporte")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Brand.red)
    }

    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "\(version) (\(build))"
    }
}
