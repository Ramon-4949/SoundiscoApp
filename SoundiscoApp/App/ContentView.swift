import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var auth = SessionViewModel()
    var body: some View {
        Group {
            if auth.initializing { LaunchView() }
            else if auth.recoveringPassword { NewPasswordView() }
            else if auth.isLocked { NavigationStack { LoginView() } }
            else if let id = auth.userID { AccountAccessGate().id(id) }
            else { NavigationStack { LoginView() } }
        }
        .tint(Brand.red)
        .environmentObject(auth)
        .task { await auth.observeSession() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { auth.lockSession() }
        }
        .onOpenURL { url in Task { await auth.handle(url) } }
        .alert(item: $auth.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("Entendido")))
        }
    }
}

struct LaunchView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            BrandMark(size: 100)
            Text("SounDisco").font(.largeTitle.bold())
            Text("PORTAL EJECUTIVO").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ProgressView().padding(.top, 24).accessibilityLabel("Cargando")
            Spacer()
            Text("Producción de eventos y audiovisuales")
                .font(.footnote).foregroundStyle(.secondary).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
            LaunchView().preferredColorScheme(.dark).previewDisplayName("Carga oscura")
        }
    }
}
