import EventKit

@MainActor
enum RemindersExporter {
    private static var exporting = false
    enum Failure: LocalizedError {
        case denied, noList, busy
        var errorDescription: String? {
            switch self {
            case .denied: "Wrist doesn't have access to Reminders. You can allow it in Settings."
            case .noList: "Create a list in Reminders, then try again."
            case .busy: "A Reminders export is already in progress."
            }
        }
    }

    /// Stable action URLs make repeat exports idempotent, including after an app restart.
    static func export(_ items: [ActionItem], from memoTitle: String) async throws -> Int {
        guard !exporting else { throw Failure.busy }
        exporting = true
        defer { exporting = false }
        let store = EKEventStore()
        guard try await store.requestFullAccessToReminders() else { throw Failure.denied }
        guard let calendar = store.defaultCalendarForNewReminders() else { throw Failure.noList }
        let predicate = store.predicateForReminders(in: nil)
        let existing: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
        let exportedURLs = Set(existing.compactMap { $0.url?.absoluteString })
        var count = 0
        for item in items where !item.isDone {
            let marker = "wrist://action/\(item.id.uuidString)"
            guard !exportedURLs.contains(marker) else { continue }
            let reminder = EKReminder(eventStore: store)
            reminder.title = item.text
            reminder.notes = "From Wrist · \(memoTitle)"
            reminder.url = URL(string: marker)
            reminder.calendar = calendar
            try store.save(reminder, commit: false)
            count += 1
        }
        if count > 0 { try store.commit() }
        return count
    }
}
