import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: SessionViewModel
    @StateObject private var model = LoginViewModel()
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            content(now: timeline.date)
        }
    }

    private func content(now: Date) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image("BrandLogo")
                        .resizable().scaledToFit()
                        .frame(width: 80, height: 80)
                        .scaleEffect(1.22)
                        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                        .padding(11)
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.04), radius: 2, y: 2)
                        .accessibilityLabel("SounDisco")
                        .padding(.bottom, 10)
                    Text("PORTAL EJECUTIVO").font(.caption.weight(.semibold)).foregroundStyle(Brand.red)
                    Text("Bienvenido de nuevo").font(.title.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Ingresa tus credenciales corporativas para continuar")
                        .font(.body).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center).padding(.top, 24).padding(.bottom, 12)
                VStack(spacing: 20) {
                    AuthField(title: "Correo electrónico", icon: "envelope", placeholder: "nombre@soundisco.com",
                              text: $model.email, keyboard: .emailAddress, contentType: .username,
                              error: model.emailError, groupedLoginStyle: true)
                    AuthField(title: "Contraseña", icon: "lock", placeholder: "Tu contraseña",
                              text: $model.password, secure: true, contentType: .password,
                              error: model.passwordError, groupedLoginStyle: true)
                    if let message = model.attemptMessage(at: now) {
                        Label(message, systemImage: "lock.fill")
                            .font(.caption).foregroundStyle(model.isLocked(at: now) ? .red : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    rememberEmail.frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                VStack(spacing: 12) {
                    PrimaryAction(title: model.busy ? "Iniciando sesión…" : "Iniciar sesión", action: { model.signIn(using: auth) })
                        .disabled(model.isLocked(at: now))
                        .shadow(color: Brand.red.opacity(0.18), radius: 7, y: 5)
                    Button {
                        Task { await auth.signInWithBiometrics() }
                    } label: {
                        HStack(spacing: 10) {
                            if auth.biometricLoginBusy { ProgressView() }
                            Label(auth.biometricLoginBusy ? "Verificando identidad…" : "Ingresar con Face ID", systemImage: "faceid")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .foregroundStyle(.primary)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("login.faceID")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { registrationPrompt }
                    VStack(spacing: 8) { registrationPrompt }
                }.font(.subheadline).padding(.top, 32).padding(.bottom, 24)
            }
            .frame(maxWidth: 440).padding(.horizontal, 20).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(model.busy || auth.biometricBusy || auth.biometricLoginBusy || auth.signingOut)
        .onAppear {
            if auth.isLocked, let email = auth.userEmail { model.email = email }
            model.refreshAttemptStatus(now: now)
        }
        .onChange(of: model.email) { _, _ in model.refreshAttemptStatus(now: now) }
        .background(Color(uiColor: .systemGroupedBackground))
        .alert(item: $model.notice) { item in
            Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("Entendido")))
        }
    }

    private var rememberEmail: some View {
        HStack(spacing: 8) {
            Toggle("Recordar correo", isOn: $model.rememberEmail).labelsHidden().fixedSize()
            Text("Recordarme").font(.caption).fixedSize()
        }
    }

    @ViewBuilder private var registrationPrompt: some View {
        Text("¿No tienes una cuenta?").foregroundStyle(.secondary)
        NavigationLink("Regístrate") { RegistrationView() }.fontWeight(.semibold)
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationStack { LoginView() }.environmentObject(SessionViewModel()).tint(Brand.red)
            NavigationStack { LoginView() }.environmentObject(SessionViewModel()).tint(Brand.red).preferredColorScheme(.dark)
        }
    }
}
