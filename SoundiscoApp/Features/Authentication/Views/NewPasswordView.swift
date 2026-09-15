import SwiftUI

struct NewPasswordView: View {
    @EnvironmentObject private var auth: SessionViewModel
    @StateObject private var model = NewPasswordViewModel()
    var body: some View {
        NavigationStack {
            Form {
                Section("Nueva contraseña") {
                    SecureField("Contraseña", text: $model.password).textContentType(.newPassword)
                    SecureField("Confirmar contraseña", text: $model.confirmation).textContentType(.newPassword)
                    Text("Mínimo 8 caracteres, letras, números y un símbolo.").font(.caption)
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
