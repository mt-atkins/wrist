import EventKit

enum RemindersExporter {
    enum Failure: LocalizedError {
        case denied
        var errorDescription: String? { "Wrist doesn't have access to Reminders. You can allow it in Settings." }
    }

    /// Adds every open action item to the default Reminders list. Returns how many were added.
    static func export(_ items: [ActionItem], from memoTitle: String) async throws -> Int {
        let store = EKEventStore()
        guard try await store.requestFullAccessToReminders() else { throw Failure.denied }
        let open = items.filter { !$0.isDone }
        for item in open {
            let reminder = EKReminder(eventStore: store)
            reminder.title = item.text
            reminder.notes = "From Wrist · \(memoTitle)"
            reminder.calendar = store.defaultCalendarForNewReminders()
            try store.save(reminder, commit: false)
        }
        try store.commit()
        return open.count
    }
}
