import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var auth: SessionViewModel
    @ObservedObject var model: ProfileViewModel
    @State private var selectedProfile: EmployeeProfile?

    var body: some View {
        Form {
            Section {
                NavigationLink { ChangePasswordView() } label: {
                    row("Cambiar contraseña", symbol: "lock.rotation")
                }
                Button {
                    selectedProfile = model.profile
                } label: {
                    HStack {
                        row("Editar perfil", symbol: "person.crop.circle")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }.foregroundStyle(.primary)
                }
                .disabled(model.profile == nil)
            }
            if model.isLoading { ProgressView("Cargando perfil…") }
            if let error = model.error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("Reintentar") { Task { await reload() } }
                }
            }
        }
        .navigationTitle("Cuenta")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Brand.red)
        .sheet(item: $selectedProfile, onDismiss: { Task { await reload() } }) { profile in
            EditProfileView(profile: profile, username: auth.displayName)
        }
    }

    private func row(_ title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Brand.red)
                .frame(width: 36, height: 36)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            Text(title)
        }.padding(.vertical, 4)
    }

    private func reload() async {
        if let id = auth.userID { await model.load(userID: id) }
    }
}
