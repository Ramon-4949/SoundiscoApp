import SwiftUI

struct NotificationBell: View {
    @EnvironmentObject private var notifications: NotificationsViewModel
    var body: some View {
        Image(systemName: "bell")
            .frame(width: 44, height: 44)
            .overlay(alignment: .topTrailing) {
                if notifications.unreadCount > 0 {
                    Text(notifications.unreadCount > 99 ? "99+" : "\(notifications.unreadCount)")
                        .font(.caption2.bold())
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Brand.red, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Notificaciones, \(notifications.unreadCount) sin leer")
    }
}
