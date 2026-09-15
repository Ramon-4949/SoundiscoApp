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
                    TextField("Correo electrónico", text: $model.email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
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
