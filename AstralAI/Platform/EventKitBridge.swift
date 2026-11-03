import Foundation
import EventKit

// MARK: - Errors

/// Localized EventKit failures surfaced to the agent (and the user).
enum EventKitError: LocalizedError {
    case remindersAccessDenied
    case eventsAccessDenied
    case noDefaultReminderList
    case noDefaultCalendar

    var errorDescription: String? {
        switch self {
        case .remindersAccessDenied:
            return L("eventkit.remindersDenied", "Platform")
        case .eventsAccessDenied:
            return L("eventkit.eventsDenied", "Platform")
        case .noDefaultReminderList:
            return L("eventkit.noReminderList", "Platform")
        case .noDefaultCalendar:
            return L("eventkit.noCalendar", "Platform")
        }
    }
}

// MARK: - Bridge

/// Creates reminders and calendar events on the user's default lists.
/// Uses the iOS 17 async full-access requests with a legacy fallback.
final class EventKitBridge {
    static let shared = EventKitBridge()

    private let store = EKEventStore()

    private init() {}

    // MARK: - Access

    /// Requests full access to Reminders (iOS 17 API with pre-17 fallback).
    func requestRemindersAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            return (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            return await withCheckedContinuation { continuation in
                store.requestAccess(to: .reminder) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Requests full access to Calendar (iOS 17 API with pre-17 fallback).
    func requestEventsAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            return (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            return await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Reminders

    /// Creates a reminder on the default reminder list. When a due date is
    /// given, the reminder fires an alarm exactly at that moment.
    @discardableResult
    func createReminder(title: String, dueDate: Date?) async throws -> String {
        guard await requestRemindersAccess() else {
            throw EventKitError.remindersAccessDenied
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate)
            reminder.alarms = [EKAlarm(absoluteDate: dueDate)]
        }
        guard let calendar = store.defaultCalendarForNewReminders() else {
            throw EventKitError.noDefaultReminderList
        }
        reminder.calendar = calendar

        try store.save(reminder, commit: true)
        return String(format: L("reminder.created", "Platform"), title)
    }

    // MARK: - Events

    /// Creates a calendar event on the default calendar. A missing end date
    /// defaults to a one-hour event.
    @discardableResult
    func createEvent(title: String, start: Date, end: Date?, notes: String?) async throws -> String {
        guard await requestEventsAccess() else {
            throw EventKitError.eventsAccessDenied
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end ?? start.addingTimeInterval(3600)
        if let notes, !notes.isEmpty {
            event.notes = notes
        }
        guard let calendar = store.defaultCalendarForNewEvents else {
            throw EventKitError.noDefaultCalendar
        }
        event.calendar = calendar

        try store.save(event, span: .thisEvent, commit: true)
        return String(format: L("event.created", "Platform"), title)
    }
}
