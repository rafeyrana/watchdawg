import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func sendArmedNotification() {
        guard AppState.shared.notificationsEnabled else { return }
        send(title: "Watchdawg", body: "The dawg is awake 🐕", sound: AppState.shared.notificationSoundEnabled)
    }

    func sendDisarmedNotification() {
        guard AppState.shared.notificationsEnabled else { return }
        send(title: "Watchdawg", body: "The dawg is napping 💤", sound: AppState.shared.notificationSoundEnabled)
    }

    func sendMotionDetectedNotification() {
        guard AppState.shared.notificationsEnabled else { return }
        send(title: "Watchdawg", body: "Motion detected! Recording started 👀", sound: AppState.shared.notificationSoundEnabled)
    }

    private func send(title: String, body: String, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound {
            content.sound = .default
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
