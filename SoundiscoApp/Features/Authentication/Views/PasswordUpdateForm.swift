import SwiftUI
import Supabase

struct PasswordHeading: View {
    let title: String
    let subtitle: String
    var symbol = "lock.rotation"
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(Brand.red)
                .frame(width: 72, height: 72)
                .background(Brand.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
            Text(title).font(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary)
        }.multilineTextAlignment(.center).padding(.vertical, 24)
    }
}

struct PasswordUpdateForm: View {
    @StateObject private var model: NewPasswordViewModel
    let onSuccess: () async -> Void
    @State private var showsRecovery = false

    init(client: SupabaseClient? = nil, requiresCurrentPassword: Bool, onSuccess: @escaping () async -> Void) {
        _model = StateObject(wrappedValue: NewPasswordViewModel(client: client, requiresCurrentPassword: requiresCurrentPassword))
        self.onSuccess = onSuccess
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                PasswordHeading(title: model.requiresCurrentPassword ? "Nueva contraseña" : "Restablecer contraseña",
                                subtitle: "Establece una nueva clave segura para tu cuenta SounDisco.")
                VStack(spacing: 20) {
                    if model.requiresCurrentPassword {
                        AuthField(title: "Contraseña actual", icon: "key", placeholder: "Tu contraseña actual",
                                  text: $model.currentPassword, secure: true, contentType: .password,
                                  error: model.currentPasswordError)
                        Button("¿La olvidaste?") { showsRecovery = true }
                        Divider()
                    }
                    AuthField(title: "Nueva contraseña", icon: "lock", placeholder: "Nueva contraseña",
                              text: $model.password, secure: true, contentType: .newPassword, error: model.passwordError)
                    ProgressView(value: Double(requirements.filter(\.1).count), total: Double(requirements.count)).tint(Brand.red)
                    AuthField(title: "Confirmar nueva contraseña", icon: "checkmark.shield", placeholder: "Repite la contraseña",
                              text: $model.confirmation, secure: true, contentType: .newPassword, error: model.confirmationError)
                }.padding(18).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 12) {
                    Text("REQUISITOS DE LA CONTRASEÑA").font(.caption.weight(.semibold))
                    ForEach(requirements, id: \.0) { item in
                        Label(item.0, systemImage: item.1 ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.1 ? Brand.red : Color.secondary)
                    }
                }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                PrimaryAction(title: model.busy ? "Actualizando…" : "Actualizar contraseña") {
                    Task { if await model.save() { await onSuccess() } }
                }
            }.padding(24).frame(maxWidth: 480).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground)).tint(Brand.red)
        .scrollDismissesKeyboard(.interactively).disabled(model.busy)
        .interactiveDismissDisabled(model.busy)
        .sheet(isPresented: $showsRecovery) { PasswordRecoveryView(initialEmail: "") }
        .alert(item: $model.notice) {
            Alert(title: Text($0.title), message: Text($0.message), dismissButton: .default(Text("Entendido")))
        }
    }

    private var requirements: [(String, Bool)] {
        [
            ("Entre 8 y 72 caracteres, sin espacios", (8...72).contains(model.password.count) && model.password.rangeOfCharacter(from: .whitespacesAndNewlines) == nil),
            ("Mayúscula y minúscula", model.password.rangeOfCharacter(from: .uppercaseLetters) != nil && model.password.rangeOfCharacter(from: .lowercaseLetters) != nil),
            ("Al menos un número", model.password.rangeOfCharacter(from: .decimalDigits) != nil),
            ("Un símbolo especial", model.password.rangeOfCharacter(from: .punctuationCharacters.union(.symbols)) != nil)
        ]
    }
}

struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false
    var body: some View {
        PasswordUpdateForm(requiresCurrentPassword: true) { saved = true }
            .navigationTitle("Contraseña").navigationBarTitleDisplayMode(.inline)
            .alert("Contraseña actualizada", isPresented: $saved) {
                Button("Aceptar") { dismiss() }
            } message: { Text("Tu nueva contraseña ya está activa.") }
    }
}

