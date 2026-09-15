import SwiftUI

struct RegistrationView: View {
    @EnvironmentObject private var auth: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = RegistrationViewModel()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Crear cuenta").font(.largeTitle.bold())
                    Text("Únete al equipo de SounDisco.").foregroundStyle(.secondary)
                }
                AuthField(title: "Nombre de usuario", icon: "person", placeholder: "juanperez",
                          text: $model.username, contentType: .username)
                AuthField(title: "Nombre completo", icon: "person.text.rectangle", placeholder: "Juan Pérez",
                          text: $model.fullName, contentType: .name, capitalization: .words)
                AuthField(title: "Correo electrónico", icon: "envelope", placeholder: "nombre@soundisco.com",
                          text: $model.email, keyboard: .emailAddress, contentType: .emailAddress)
                AuthField(title: "Número de teléfono", icon: "phone", placeholder: "829-588-0000",
                          text: $model.phone, keyboard: .phonePad, contentType: .telephoneNumber)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cargo en la empresa").font(.subheadline.weight(.medium))
                    Picker("Cargo", selection: $model.position) {
                        ForEach(model.positions, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8).background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 10) {
                    AuthField(title: "Contraseña", icon: "lock", placeholder: "Crea una contraseña",
                              text: $model.password, secure: true, contentType: .newPassword)
                    PasswordRequirements(password: model.password)
                }
                AuthField(title: "Confirmar contraseña", icon: "lock", placeholder: "Repite tu contraseña",
                          text: $model.confirmation, secure: true, contentType: .newPassword)
                Toggle(isOn: $model.acceptedTerms) {
                    Text("Acepto los términos de servicio y la política de privacidad.").font(.subheadline)
                }
                HStack {
                    Button("Términos") { model.legalNotice("Términos de servicio") }
                    Spacer()
                    Button("Privacidad") { model.legalNotice("Política de privacidad") }
                }.font(.subheadline)
                PrimaryAction(title: model.busy ? "Creando cuenta…" : "Crear cuenta", action: { model.register(using: auth) })
                Button("Ya tengo una cuenta. Iniciar sesión") { dismiss() }
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .frame(maxWidth: 440).padding(24).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(model.busy)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $model.notice) { item in
            Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("Entendido")))
        }
    }
}

private struct PasswordRequirements: View {
    let password: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<4) { index in
                    Capsule().fill(index < AuthValidation.passwordScore(password) ? Brand.red : Color(uiColor: .separator))
                        .frame(height: 4)
                }
            }.accessibilityHidden(true)
            Text("Mínimo 8 caracteres, letras, números y un símbolo.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct RegistrationView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationStack { RegistrationView() }.environmentObject(SessionViewModel()).tint(Brand.red)
            NavigationStack { RegistrationView() }.environmentObject(SessionViewModel()).tint(Brand.red).preferredColorScheme(.dark)
        }
    }
}
