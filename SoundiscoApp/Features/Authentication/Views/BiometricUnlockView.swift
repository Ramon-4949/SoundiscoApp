import SwiftUI

struct BiometricUnlockView: View {
    @EnvironmentObject private var auth: SessionViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            BrandMark(size: 100)
            Text("Sesión protegida").font(.title.bold())
            Button {
                Task { await auth.unlockSession() }
            } label: {
                Label("Desbloquear con biometría", systemImage: "faceid")
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent).tint(Brand.red)
            .disabled(auth.biometricBusy || auth.signingOut)
            if auth.biometricBusy { ProgressView("Verificando identidad…") }
            Button("Acceder con correo y contraseña") {
                Task { await auth.usePasswordInstead() }
            }
            .disabled(auth.biometricBusy || auth.signingOut)
            Spacer()
        }
        .padding(24).frame(maxWidth: 440).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
