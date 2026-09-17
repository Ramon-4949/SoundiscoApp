import SwiftUI

struct NotificationBell: View {
    @EnvironmentObject private var notifications: NotificationsViewModel
    var body: some View {
        Label("Notificaciones", systemImage: notifications.unreadCount > 0 ? "bell.badge" : "bell")
            .accessibilityLabel("Notificaciones, \(notifications.unreadCount) sin leer")
    }
}
