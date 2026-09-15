import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var auth: SessionViewModel
    @StateObject private var model = ProfileViewModel()
    var body: some View {
        Form {
            Section {
                Label(model.profile?.nombre_completo ?? auth.displayName, systemImage: "person.crop.circle")
                if let email = auth.userEmail { Text(email).textSelection(.enabled) }
                if let phone = model.profile?.telefono { Label(phone, systemImage: "phone") }
            }
            if let error = model.error {
                Section { Text(error).foregroundStyle(.secondary) }
            }
            Section {
                Button("Cerrar sesión", role: .destructive) { Task { await auth.signOut() } }
            }
        }.navigationTitle("Mi perfil")
        .task(id: auth.userID) { if let id = auth.userID { await model.load(userID: id) } }
    }
}
