import SwiftUI

struct PasswordRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: PasswordRecoveryViewModel
    init(initialEmail: String) {
        _model = StateObject(wrappedValue: PasswordRecoveryViewModel(email: initialEmail))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Introduce tu correo corporativo para recuperar el acceso.")
                    AuthField(title: "Correo electrónico", icon: "envelope", placeholder: "nombre@soundisco.com",
                              text: $model.email, keyboard: .emailAddress, contentType: .emailAddress,
                              error: model.emailError)
                }
                Button("Enviar enlace") { Task { await model.send() } }.disabled(model.busy)
                if model.busy { ProgressView("Enviando…") }
            }
            .navigationTitle("Recuperar acceso").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
            .alert(item: $model.notice) { item in
                Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("Entendido")))
            }
        }.tint(Brand.red)
    }
}
