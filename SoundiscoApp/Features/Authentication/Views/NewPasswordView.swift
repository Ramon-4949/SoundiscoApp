import SwiftUI

struct NewPasswordView: View {
    @EnvironmentObject private var auth: SessionViewModel
    var body: some View {
        NavigationStack {
            PasswordUpdateForm(requiresCurrentPassword: false) {
                await auth.signOut()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { Task { await auth.signOut() } }
                }
            }
        }
    }
}
