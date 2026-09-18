import UIKit
import UserNotifications
import Combine
import Supabase

struct NotificationRoute: Identifiable {
    let id: UUID
    let recipient: UUID
}

@MainActor
final class PushNotificationService: ObservableObject {
    static let shared = PushNotificationService()
    @Published var route: NotificationRoute?
    @Published private(set) var permissionDenied = false
    @Published var failure: String?
    private var token: String?
    private var userID: UUID?
    private var registered = UserDefaults.standard.bool(forKey: "push.registered")
    private let client = SupabaseService.client
    private let installation: UUID = {
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: "push.installation"), let id = UUID(uuidString: value) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: "push.installation")
        return id
    }()

    func connect(userID: UUID) async {
        self.userID = userID
        if let route, route.recipient != userID { self.route = nil }
        await requestPermission()
        await registerToken()
    }

    func requestPermission() async {
        do {
            let center = UNUserNotificationCenter.current()
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                settings = await center.notificationSettings()
            }
            permissionDenied = settings.authorizationStatus == .denied
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch { failure = "No se pudieron activar los avisos: \(error.localizedDescription)" }
    }

    func receivedToken(_ data: Data) async {
        token = data.map { String(format: "%02x", $0) }.joined()
        await registerToken()
    }

    private func registerToken() async {
        guard let token, let userID else { return }
        struct Registration: Encodable {
            let p_installation: UUID
            let p_token: String
            let p_environment: String
        }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        do {
            try await client.rpc("register_push_device", params: Registration(
                p_installation: installation, p_token: token, p_environment: environment)).execute()
            if self.userID == userID {
                registered = true
                UserDefaults.standard.set(true, forKey: "push.registered")
                failure = nil
            }
        } catch { failure = "No se pudo registrar este dispositivo para avisos. \(AuthNotice.failure(error).message)" }
    }

    // Called before a real sign-out, while the JWT can still authorize removal.
    func disconnect() async throws {
        struct Params: Encodable { let p_installation: UUID }
        if registered {
            try await client.rpc("unregister_push_device", params: Params(p_installation: installation)).execute()
        }
        registered = false
        UserDefaults.standard.set(false, forKey: "push.registered")
        userID = nil
        route = nil
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

final class NotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in await PushNotificationService.shared.receivedToken(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushNotificationService.shared.failure = "No se pudieron registrar los avisos push: \(error.localizedDescription)" }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        let data = response.notification.request.content.userInfo
        if let raw = data["notification_id"] as? String, let id = UUID(uuidString: raw),
           let owner = data["recipient_id"] as? String, let recipient = UUID(uuidString: owner) {
            Task { @MainActor in PushNotificationService.shared.route = NotificationRoute(id: id, recipient: recipient) }
        }
        completionHandler()
    }
}
