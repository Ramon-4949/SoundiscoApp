import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var auth: SessionViewModel
    @StateObject private var model = ProfileViewModel()
    @State private var confirmSignOut = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 80)).foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(nonblank(model.profile?.nombre_completo) ?? auth.displayName)
                        .font(.title2.bold()).multilineTextAlignment(.center)
                    if model.isLoading { ProgressView("Cargando perfil…") }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
            }

            Section("Información") {
                information("Correo corporativo", value: auth.userEmail, symbol: "envelope")
                information("Número de teléfono", value: model.profile?.telefono, symbol: "phone")
                information("Cargo", value: nonblank(model.profile?.cargo) ?? nonblank(auth.jobTitle) ?? roleTitle,
                            symbol: "building.2")
            }

            if let error = model.error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("Reintentar") { Task { await load() } }
                }
            }

            Section("Preferencias y seguridad") {
                Toggle(isOn: Binding(get: { auth.biometricEnabled }, set: { value in
                    Task { await auth.setBiometricEnabled(value) }
                })) {
                    HStack(spacing: 12) {
                        icon("faceid")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Face ID / Biometría")
                            Text("Acceso a la aplicación").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(auth.biometricBusy || auth.signingOut)
                .tint(Brand.red)
                if auth.biometricBusy { ProgressView("Verificando identidad…") }

                LabeledContent {
                    Text("Español (DO)").foregroundStyle(.secondary)
                } label: {
                    Label("Idioma de interfaz", systemImage: "globe")
                }
                .disabled(true)
                .accessibilityHint("El cambio de idioma aún no está disponible")
            }

            Section {
                Button(role: .destructive) { confirmSignOut = true } label: {
                    HStack {
                        Spacer()
                        if auth.signingOut { ProgressView() }
                        Label(auth.signingOut ? "Cerrando sesión…" : "Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.headline)
                        Spacer()
                    }.padding(.vertical, 8)
                }
                .disabled(auth.signingOut || auth.biometricBusy)
            }
        }
        .navigationTitle("Mi perfil")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Brand.red)
        .task(id: auth.userID) { await load() }
        .refreshable { await load() }
        .confirmationDialog("¿Cerrar sesión?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Cerrar sesión", role: .destructive) { Task { await auth.signOut() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(auth.biometricEnabled
                 ? "La aplicación quedará bloqueada. Podrás volver a entrar con Face ID."
                 : "Necesitarás tu correo y contraseña para volver a entrar.")
        }
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol).foregroundStyle(Brand.red)
            .frame(width: 36, height: 36)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }

    private func information(_ title: String, value: String?, symbol: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            icon(symbol)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(nonblank(value) ?? "No registrado")
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, 4)
    }

    private var roleTitle: String? {
        switch model.profile?.rol {
        case "admin": "Administración"
        case "tecnico": "Técnico"
        default: nil
        }
    }

    private func nonblank(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private func load() async {
        if let id = auth.userID { await model.load(userID: id) }
    }
}
