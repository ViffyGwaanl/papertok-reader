import Foundation
import Flutter
import EventKit

final class RemindersChannel {
  private let store = EKEventStore()

  func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "ai.papertok.paperreader/reminders",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "Reminders bridge unavailable", details: nil))
        return
      }

      switch call.method {
      case "create":
        let args = call.arguments as? [String: Any]
        self.handleCreate(args: args, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func requestAccessIfNeeded(completion: @escaping (Bool, Error?) -> Void) {
    store.requestAccess(to: .reminder) { granted, error in
      completion(granted, error)
    }
  }

  private func parseIso(_ raw: String) -> Date? {
    let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { return nil }

    // Try with fractional seconds first.
    let fmt1 = ISO8601DateFormatter()
    fmt1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = fmt1.date(from: s) { return d }

    let fmt2 = ISO8601DateFormatter()
    fmt2.formatOptions = [.withInternetDateTime]
    return fmt2.date(from: s)
  }

  private func handleCreate(args: [String: Any]?, result: @escaping FlutterResult) {
    guard let args = args else {
      result(FlutterError(code: "bad_args", message: "Missing arguments", details: nil))
      return
    }

    let title = (args["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if title.isEmpty {
      result(FlutterError(code: "bad_args", message: "title is required", details: nil))
      return
    }

    requestAccessIfNeeded { granted, error in
      if let error = error {
        result(FlutterError(code: "permission", message: "Permission error: \(error.localizedDescription)", details: nil))
        return
      }
      if !granted {
        result(FlutterError(code: "permissionDenied", message: "Reminders permission denied", details: nil))
        return
      }

      let reminder = EKReminder(eventStore: self.store)
      reminder.title = title

      if let notes = args["notes"] as? String, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        reminder.notes = notes
      }

      if let dueIso = args["dueIso"] as? String, let dueDate = self.parseIso(dueIso) {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: dueDate)
        reminder.dueDateComponents = comps
      }

      if let listId = args["listId"] as? String {
        let clean = listId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty, let cal = self.store.calendar(withIdentifier: clean) {
          reminder.calendar = cal
        }
      }

      if reminder.calendar == nil {
        reminder.calendar = self.store.defaultCalendarForNewReminders()
      }

      do {
        try self.store.save(reminder, commit: true)
        result([
          "id": reminder.calendarItemIdentifier,
          "title": reminder.title,
          "calendarId": reminder.calendar.calendarIdentifier
        ])
      } catch {
        result(FlutterError(code: "save_failed", message: "Failed to save reminder: \(error.localizedDescription)", details: nil))
      }
    }
  }
}
