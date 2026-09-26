import UIKit
import UserNotifications
import Combine
import Supabase
import OSLog

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
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SoundiscoApp", category: "Push")
    private let installation: UUID = {
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: "push.installation"), let id = UUID(uuidString: value) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: "push.installation")
        return id
    }()

    func connect(userID: UUID) async {
        guard !Task.isCancelled,
              let session = try? await client.auth.session,
              session.user.id == userID else { return }
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
            logger.info("Push permission=\(settings.authorizationStatus.rawValue) sound=\(settings.soundSetting.rawValue)")
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch { failure = "No se pudieron activar los avisos: \(error.localizedDescription)" }
    }

    func receivedToken(_ data: Data) async {
        token = data.map { String(format: "%02x", $0) }.joined()
        logger.info("APNs device token received")
        await registerToken()
    }

    private func registerToken() async {
        guard let token, let userID else { return }
        struct Registration: Encodable {
            let p_installation: UUID
            let p_token: String
            let p_environment: String
        }
        guard let environment = pushEnvironment else {
            failure = "La configuración de avisos de esta versión no es válida. Actualiza la app e inténtalo nuevamente."
            return
        }
        do {
            guard !Task.isCancelled,
                  try await client.auth.session.user.id == userID,
                  self.userID == userID else { return }
            try await client.rpc("register_push_device", params: Registration(
                p_installation: installation, p_token: token, p_environment: environment)).execute()
            if self.userID == userID {
                registered = true
                UserDefaults.standard.set(true, forKey: "push.registered")
                failure = nil
                logger.info("Push device registered environment=\(environment, privacy: .public)")
            }
        } catch {
            guard !Task.isCancelled, self.userID == userID else { return }
            failure = "No se pudo registrar este dispositivo para avisos. \(AuthNotice.failure(error).message)"
            logger.error("register_push_device failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private var pushEnvironment: String? {
        switch Bundle.main.object(forInfoDictionaryKey: "APNSEnvironment") as? String {
        case "development": return "sandbox"
        case "production": return "production"
        default: return nil
        }
    }

    // Called before a real sign-out, while the JWT can still authorize removal.
    func disconnect() async throws {
        struct Params: Encodable { let p_installation: UUID }
        if registered {
            try await client.rpc("unregister_push_device", params: Params(p_installation: installation)).execute()
        }
        await clearLocalRegistration()
    }

    // Account deletion already removed the device on the server.
    func clearLocalRegistration() async {
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
