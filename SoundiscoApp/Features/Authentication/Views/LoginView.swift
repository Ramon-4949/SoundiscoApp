import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: SessionViewModel
    @StateObject private var model = LoginViewModel()
    @State private var recoveryPresented = false
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    BrandMark().padding(14)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                    Text("SOUNDisco".uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Brand.red)
                    Text("Bienvenido de nuevo").font(.largeTitle.bold())
                    Text("Ingresa tus credenciales corporativas para continuar").foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center).padding(.top, 28)
                VStack(spacing: 20) {
                    AuthField(title: "Correo electrónico", icon: "envelope", placeholder: "nombre@soundisco.com",
                              text: $model.email, keyboard: .emailAddress, contentType: .username)
                    AuthField(title: "Contraseña", icon: "lock", placeholder: "Tu contraseña",
                              text: $model.password, secure: true, contentType: .password)
                    Toggle("Recordar correo", isOn: $model.rememberEmail).font(.subheadline)
                    Button("¿Olvidaste tu contraseña?") { recoveryPresented = true }
                        .font(.subheadline).frame(maxWidth: .infinity, alignment: .trailing)
                }
                VStack(spacing: 12) {
                    PrimaryAction(title: model.busy ? "Iniciando sesión…" : "Iniciar sesión", action: { model.signIn(using: auth) })
                    Button {
                        model.notice = AuthNotice(title: "Acceso con Face ID", message: "Primero inicia sesión con tu correo y contraseña para habilitar el acceso biométrico.")
                    } label: {
                        Label("Ingresar con Face ID", systemImage: "faceid")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .foregroundStyle(.primary)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                }
                VStack(spacing: 8) {
                    Text("¿No tienes una cuenta?").foregroundStyle(.secondary)
                    NavigationLink("Regístrate") { RegistrationView() }.fontWeight(.semibold)
                }.font(.subheadline).padding(.vertical, 20)
            }
            .frame(maxWidth: 440).padding(.horizontal, 24).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(model.busy)
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: $recoveryPresented) { PasswordRecoveryView(initialEmail: model.email) }
        .alert(item: $model.notice) { item in
            Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("Entendido")))
        }
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
