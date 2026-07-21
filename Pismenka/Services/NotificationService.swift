//
//  NotificationService.swift
//  Pismenka
//
//  Parent opt-in, local-only daily reminder scheduling.
//

import Foundation
import UserNotifications

@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    private static let dailyReminderHour = 7
    private static let dailyReminderMinute = 0

    private let reminderIdentifier = "pismenka.daily.reminder"
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// `layer` controls the reminder copy ("letter" vs "number") so the
    /// notification matches the mode the family is currently playing.
    func updateDailyReminder(enabled: Bool, layer: LearningLayer = .letters) {
        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
            return
        }

        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            Task { @MainActor in
                self?.scheduleDailyReminder(layer: layer)
            }
        }
    }

    private func scheduleDailyReminder(layer: LearningLayer) {
        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Písmenka"
        content.body = layer == .numbers ? "Ready for today’s number?" : "Ready for today’s letter?"
        content.sound = .default

        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = .autoupdatingCurrent
        components.hour = Self.dailyReminderHour
        components.minute = Self.dailyReminderMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: reminderIdentifier, content: content, trigger: trigger)
        center.add(request)
    }
}
