import SwiftUI

struct PasswordRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: PasswordRecoveryViewModel

    init(initialEmail: String) {
        _model = StateObject(wrappedValue: PasswordRecoveryViewModel(email: initialEmail))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.step == .password {
                    PasswordUpdateForm(client: model.client, requiresCurrentPassword: false) {
                        await model.finish()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 28) {
                            PasswordHeading(title: title, subtitle: subtitle, symbol: model.step == .code ? "envelope.badge.shield.half.filled" : "lock.rotation")
                            if model.step == .email {
                                AuthField(title: "Correo electrónico registrado", icon: "envelope",
                                          placeholder: "nombre@empresa.com", text: $model.email,
                                          keyboard: .emailAddress, contentType: .emailAddress, error: model.emailError)
                                PrimaryAction(title: "Enviar código de recuperación") { Task { await model.send() } }
                            } else if model.step == .code {
                                Text(model.sentEmail).font(.subheadline.weight(.medium)).textSelection(.enabled)
                                EmailCodeInput(code: $model.code)
                                PrimaryAction(title: "Verificar y continuar") { Task { await model.verify() } }
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    let remaining = max(0, Int(model.resendAt.timeIntervalSince(context.date).rounded(.up)))
                                    Button(remaining > 0 ? "Reenviar código (\(remaining)s)" : "Reenviar código") {
                                        Task { await model.send() }
                                    }.disabled(remaining > 0 || model.busy)
                                }
                            } else {
                                PrimaryAction(title: "Volver") { dismiss() }
                            }
                            if model.busy { ProgressView() }
                        }.padding(24).frame(maxWidth: 480).frame(maxWidth: .infinity)
                    }.background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .disabled(model.busy)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { Task { await model.cancel(); dismiss() } }.disabled(model.busy)
                }
            }
            .alert(item: $model.notice) {
                Alert(title: Text($0.title), message: Text($0.message), dismissButton: .default(Text("Entendido")))
            }
        }.tint(Brand.red).interactiveDismissDisabled(model.busy || model.step == .password)
        .onDisappear { Task { await model.cancel() } }
    }

    private var title: String {
        switch model.step {
        case .email: "Recuperar contraseña"
        case .code: "Verifica tu identidad"
        case .password: "Restablecer contraseña"
        case .complete: "Contraseña actualizada"
        }
    }

    private var subtitle: String {
        switch model.step {
        case .email: "Introduce tu correo registrado. Te enviaremos un código para restablecer tu acceso."
        case .code: "Si el correo está registrado, recibirás un código de verificación. Escríbelo para continuar."
        case .password: ""
        case .complete: "Ya puedes iniciar sesión con tu nueva contraseña."
        }
    }
}

struct EmailCodeInput: View {
    @Binding var code: String
    @FocusState private var focus: Int?
    private var count: Int { max(6, min(10, code.count)) }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                TextField("", text: Binding(get: {
                    let digits = Array(code)
                    return index < digits.count ? String(digits[index]) : ""
                }, set: { update($0, at: index) }))
                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                .multilineTextAlignment(.center).font(.title3.bold())
                .focused($focus, equals: index)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(focus == index ? Brand.red : Color(uiColor: .separator)))
                .accessibilityLabel("Dígito \(index + 1)")
            }
        }.onAppear { focus = 0 }
    }

    private func update(_ value: String, at index: Int) {
        let incoming = value.filter { $0.isASCII && $0.isNumber }
        if incoming.count > 1 {
            code = String(incoming.prefix(10))
            focus = min(code.count, count - 1)
            return
        }
        var digits = Array(code)
        if incoming.isEmpty {
            if index < digits.count { digits.remove(at: index) }
            code = String(digits)
            focus = max(0, index - 1)
        } else {
            if index < digits.count { digits[index] = incoming.first! }
            else { digits.append(incoming.first!) }
            code = String(digits.prefix(10))
            focus = min(index + 1, count - 1)
        }
    }
}
