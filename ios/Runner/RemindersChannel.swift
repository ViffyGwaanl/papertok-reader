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
      case "listLists":
        self.handleListLists(result: result)
      case "list":
        let args = call.arguments as? [String: Any]
        self.handleList(args: args, result: result)
      case "delete":
        let args = call.arguments as? [String: Any]
        self.handleDelete(args: args, result: result)
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

  private func handleListLists(result: @escaping FlutterResult) {
    requestAccessIfNeeded { granted, error in
      if let error = error {
        result(FlutterError(code: "permission", message: "Permission error: \(error.localizedDescription)", details: nil))
        return
      }
      if !granted {
        result(FlutterError(code: "permissionDenied", message: "Reminders permission denied", details: nil))
        return
      }

      let cals = self.store.calendars(for: .reminder)
      let defaultId = self.store.defaultCalendarForNewReminders()?.calendarIdentifier

      let lists: [[String: Any]] = cals.map { cal in
        return [
          "id": cal.calendarIdentifier,
          "title": cal.title,
          "isDefault": (defaultId != nil && cal.calendarIdentifier == defaultId!)
        ]
      }

      result(["lists": lists])
    }
  }

  private func handleList(args: [String: Any]?, result: @escaping FlutterResult) {
    guard let args = args else {
      result(FlutterError(code: "bad_args", message: "Missing arguments", details: nil))
      return
    }

    let listIds = args["listIds"] as? [String] ?? []
    if listIds.isEmpty {
      result(FlutterError(code: "bad_args", message: "listIds is required", details: nil))
      return
    }

    let startIso = (args["startIso"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let endIso = (args["endIso"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    guard let startDate = parseIso(startIso), let endDate = parseIso(endIso) else {
      result(FlutterError(code: "bad_args", message: "startIso/endIso must be valid ISO-8601", details: nil))
      return
    }

    let includeCompleted = args["includeCompleted"] as? Bool ?? false
    let includeUndated = args["includeUndated"] as? Bool ?? false

    let limit: Int = {
      if let n = args["limit"] as? NSNumber { return max(1, min(1000, n.intValue)) }
      if let s = args["limit"] as? String, let n = Int(s) { return max(1, min(1000, n)) }
      return 200
    }()

    requestAccessIfNeeded { granted, error in
      if let error = error {
        result(FlutterError(code: "permission", message: "Permission error: \(error.localizedDescription)", details: nil))
        return
      }
      if !granted {
        result(FlutterError(code: "permissionDenied", message: "Reminders permission denied", details: nil))
        return
      }

      let calendars: [EKCalendar] = listIds.compactMap { id in
        let clean = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return nil }
        return self.store.calendar(withIdentifier: clean)
      }

      if calendars.isEmpty {
        result(FlutterError(code: "bad_args", message: "No valid listIds found", details: nil))
        return
      }

      let predicate = self.store.predicateForReminders(in: calendars)
      self.store.fetchReminders(matching: predicate) { reminders in
        let list = reminders ?? []
        var items: [[String: Any]] = []

        func isoString(_ date: Date) -> String {
          let fmt = ISO8601DateFormatter()
          fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
          return fmt.string(from: date)
        }

        for r in list {
          if !includeCompleted && r.isCompleted { continue }

          var dueDate: Date? = nil
          if let comps = r.dueDateComponents {
            dueDate = Calendar.current.date(from: comps)
          }

          if let d = dueDate {
            if d < startDate || d > endDate { continue }
          } else {
            if !includeUndated { continue }
          }

          var completionIso: String? = nil
          if let cd = r.completionDate {
            completionIso = isoString(cd)
          }

          items.append([
            "id": r.calendarItemIdentifier,
            "title": r.title ?? "",
            "notes": r.notes ?? "",
            "listId": r.calendar.calendarIdentifier,
            "completed": r.isCompleted,
            "completionIso": completionIso as Any,
            "dueIso": (dueDate != nil) ? isoString(dueDate!) : NSNull()
          ])

          if items.count >= limit { break }
        }

        // Sort by due date (undated at the end).
        items.sort { a, b in
          let aDue = a["dueIso"] as? String
          let bDue = b["dueIso"] as? String
          if aDue == nil && bDue == nil { return (a["title"] as? String ?? "") < (b["title"] as? String ?? "") }
          if aDue == nil { return false }
          if bDue == nil { return true }
          return aDue! < bDue!
        }

        result(["reminders": items])
      }
    }
  }

  private func handleDelete(args: [String: Any]?, result: @escaping FlutterResult) {
    guard let args = args else {
      result(FlutterError(code: "bad_args", message: "Missing arguments", details: nil))
      return
    }

    let reminderId = (args["reminderId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if reminderId.isEmpty {
      result(FlutterError(code: "bad_args", message: "reminderId is required", details: nil))
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

      guard let item = self.store.calendarItem(withIdentifier: reminderId) as? EKReminder else {
        result(FlutterError(code: "not_found", message: "Reminder not found", details: nil))
        return
      }

      do {
        try self.store.remove(item, commit: true)
        result(["ok": true, "id": reminderId])
      } catch {
        result(FlutterError(code: "delete_failed", message: "Failed to delete reminder: \(error.localizedDescription)", details: nil))
      }
    }
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
