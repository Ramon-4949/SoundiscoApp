import SwiftUI

struct NewPasswordView: View {
    @EnvironmentObject private var auth: SessionViewModel
    @StateObject private var model = NewPasswordViewModel()
    var body: some View {
        NavigationStack {
            Form {
                Section("Nueva contraseña") {
                    AuthField(title: "Contraseña", icon: "lock", placeholder: "Nueva contraseña",
                              text: $model.password, secure: true, contentType: .newPassword,
                              error: model.passwordError)
                    AuthField(title: "Confirmar contraseña", icon: "lock", placeholder: "Repite la contraseña",
                              text: $model.confirmation, secure: true, contentType: .newPassword,
                              error: model.confirmationError)
                    Text("Mínimo 8 caracteres, mayúscula, minúscula, número y símbolo; sin espacios.").font(.caption)
                }
                Button("Guardar contraseña") {
                    Task { if await model.save() { auth.recoveringPassword = false } }
                }.disabled(model.busy)
                Button("Cancelar", role: .cancel) { Task { await auth.signOut() } }.disabled(model.busy)
            }
            .navigationTitle("Restablecer acceso")
            .alert(item: $model.notice) { item in
                Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("Entendido")))
            }
        }
    }
}
