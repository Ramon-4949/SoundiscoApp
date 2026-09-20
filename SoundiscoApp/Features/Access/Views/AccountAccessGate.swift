import SwiftUI

struct AccountAccessGate: View {
    @EnvironmentObject private var auth: SessionViewModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AccountAccessViewModel()

    var body: some View {
        Group {
            if model.state == .aprobada {
                HomeView()
            } else {
                NavigationStack {
                    VStack(spacing: 22) {
                        Spacer()
                        Image(systemName: model.state == .rechazada ? "person.crop.circle.badge.xmark" : "person.crop.circle.badge.clock")
                            .font(.system(size: 64)).foregroundStyle(Brand.red)
                        Text(model.failure != nil ? "No se pudo verificar el acceso" : model.state == .rechazada ? "Acceso no aprobado" : model.state == nil ? "Verificando acceso" : "Cuenta en revisión")
                            .font(.title2.bold())
                        Text(model.failure ?? (model.state == .rechazada
                            ? "Un administrador rechazó tu solicitud. Contacta con SounDisco para consultar tu caso."
                            : model.state == nil ? "Consultando el estado de tu cuenta…" : "Tu cuenta está creada y espera la aprobación de un administrador. La revisión tarda aproximadamente 24 horas. Te avisaremos cuando se apruebe tu acceso."))
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        if model.state == nil && model.failure == nil { ProgressView("Verificando acceso…") }
                        Button("Consultar estado") { Task { await model.refresh() } }
                            .buttonStyle(.borderedProminent)
                        NavigationLink("Mi perfil") { ProfileView() }
                        Button("Cerrar sesión", role: .destructive) { Task { await auth.usePasswordInstead() } }
                        Spacer()
                    }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(uiColor: .systemGroupedBackground))
                }
            }
        }
        .task {
            await model.refresh()
            if let id = auth.userID { await PushNotificationService.shared.connect(userID: id) }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                if scenePhase == .active { await model.refresh() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }
}
