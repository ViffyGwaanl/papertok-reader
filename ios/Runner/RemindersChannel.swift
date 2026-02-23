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
      case "listLists":
        self.handleListLists(result: result)
      case "createList":
        self.handleCreateList(args: call.arguments as? [String: Any], result: result)
      case "renameList":
        self.handleRenameList(args: call.arguments as? [String: Any], result: result)
      case "deleteList":
        self.handleDeleteList(args: call.arguments as? [String: Any], result: result)

      case "list":
        self.handleList(args: call.arguments as? [String: Any], result: result)
      case "get":
        self.handleGet(args: call.arguments as? [String: Any], result: result)
      case "create":
        self.handleCreate(args: call.arguments as? [String: Any], result: result)
      case "update":
        self.handleUpdate(args: call.arguments as? [String: Any], result: result)
      case "complete":
        self.handleComplete(args: call.arguments as? [String: Any], completed: true, result: result)
      case "uncomplete":
        self.handleComplete(args: call.arguments as? [String: Any], completed: false, result: result)
      case "delete":
        self.handleDelete(args: call.arguments as? [String: Any], result: result)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Helpers

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

  private func isoString(_ date: Date) -> String {
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fmt.string(from: date)
  }

  private func parseBool(_ raw: Any?, fallback: Bool) -> Bool {
    if let b = raw as? Bool { return b }
    let s = (raw as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if s == "true" { return true }
    if s == "false" { return false }
    return fallback
  }

  private func parseInt(_ raw: Any?, fallback: Int) -> Int {
    if let n = raw as? NSNumber { return n.intValue }
    if let s = raw as? String, let n = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return n }
    return fallback
  }

  private func truncate(_ s: String, maxLen: Int) -> String {
    if maxLen <= 0 { return "" }
    if s.count <= maxLen { return s }
    let idx = s.index(s.startIndex, offsetBy: maxLen)
    return String(s[..<idx])
  }

  private func reminderToMap(
    _ r: EKReminder,
    includeNotes: Bool,
    notesMaxLen: Int
  ) -> [String: Any] {
    var dueDate: Date? = nil
    if let comps = r.dueDateComponents {
      dueDate = Calendar.current.date(from: comps)
    }

    var completionIso: String? = nil
    if let cd = r.completionDate {
      completionIso = isoString(cd)
    }

    var m: [String: Any] = [
      "id": r.calendarItemIdentifier,
      "title": r.title ?? "",
      "listId": r.calendar.calendarIdentifier,
      "completed": r.isCompleted,
      "completionIso": completionIso as Any,
      "dueIso": (dueDate != nil) ? isoString(dueDate!) : NSNull()
    ]

    if r.priority != 0 {
      m["priority"] = r.priority
    }

    if let url = r.url?.absoluteString, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      m["url"] = url
    }

    if includeNotes {
      let notes = (r.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if !notes.isEmpty {
        m["notes"] = truncate(notes, maxLen: notesMaxLen)
        m["notesTruncated"] = notes.count > notesMaxLen
      }
    }

    return m
  }

  private func parseAlarmMinutesArray(_ raw: Any?) -> [Int]? {
    if raw == nil { return nil }
    if let n = raw as? NSNumber {
      return [n.intValue]
    }
    if let list = raw as? [Any] {
      let mins = list.compactMap { elem -> Int? in
        if let n = elem as? NSNumber { return n.intValue }
        if let s = elem as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
      }
      return mins
    }
    return nil
  }

  private func applyReminderAlarms(reminder: EKReminder, dueDate: Date, alarmMinutes: [Int]) {
    // For reminders, use absolute alarms (more predictable than relative offsets).
    let alarms: [EKAlarm] = alarmMinutes
      .map { $0 }
      .filter { $0 >= 0 && $0 <= 60 * 24 * 365 }
      .map { minutes in
        let alarmDate = dueDate.addingTimeInterval(TimeInterval(-minutes * 60))
        return EKAlarm(absoluteDate: alarmDate)
      }

    reminder.alarms = alarms
  }

  // MARK: - Lists (Calendars)

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

  private func handleCreateList(args: [String: Any]?, result: @escaping FlutterResult) {
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

      let cal = EKCalendar(for: .reminder, eventStore: self.store)
      cal.title = title

      if let defaultCal = self.store.defaultCalendarForNewReminders() {
        cal.source = defaultCal.source
      } else if let src = self.store.sources.first {
        cal.source = src
      }

      do {
        try self.store.saveCalendar(cal, commit: true)
        result([
          "id": cal.calendarIdentifier,
          "title": cal.title
        ])
      } catch {
        result(FlutterError(code: "save_failed", message: "Failed to create list: \(error.localizedDescription)", details: nil))
      }
    }
  }

  private func handleRenameList(args: [String: Any]?, result: @escaping FlutterResult) {
    guard let args = args else {
      result(FlutterError(code: "bad_args", message: "Missing arguments", details: nil))
      return
    }

    let listId = (args["listId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let title = (args["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if listId.isEmpty || title.isEmpty {
      result(FlutterError(code: "bad_args", message: "listId and title are required", details: nil))
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

      guard let cal = self.store.calendar(withIdentifier: listId) else {
        result(FlutterError(code: "not_found", message: "List not found", details: nil))
        return
      }

      cal.title = title
      do {
        try self.store.saveCalendar(cal, commit: true)
        result(["ok": true, "id": cal.calendarIdentifier, "title": cal.title])
      } catch {
        result(FlutterError(code: "save_failed", message: "Failed to rename list: \(error.localizedDescription)", details: nil))
      }
    }
  }

  private func handleDeleteList(args: [String: Any]?, result: @escaping FlutterResult) {
    guard let args = args else {
      result(FlutterError(code: "bad_args", message: "Missing arguments", details: nil))
      return
    }

    let listId = (args["listId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if listId.isEmpty {
      result(FlutterError(code: "bad_args", message: "listId is required", details: nil))
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

      guard let cal = self.store.calendar(withIdentifier: listId) else {
        result(FlutterError(code: "not_found", message: "List not found", details: nil))
        return
      }

      do {
        try self.store.removeCalendar(cal, commit: true)
        result(["ok": true, "id": listId])
      } catch {
        result(FlutterError(code: "delete_failed", message: "Failed to delete list: \(error.localizedDescription)", details: nil))
      }
    }
  }

  // MARK: - Reminders

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

    let startDate = parseIso(startIso) ?? Date()
    let days = max(1, min(60, parseInt(args["days"], fallback: 7)))
    let endDate = parseIso(endIso) ?? startDate.addingTimeInterval(TimeInterval(days * 24 * 3600))

    let includeCompleted = parseBool(args["includeCompleted"], fallback: false)
    let includeUndated = parseBool(args["includeUndated"], fallback: false)

    let includeNotes = parseBool(args["includeNotes"], fallback: false)
    let notesMaxLen = max(0, min(8000, parseInt(args["notesMaxLen"], fallback: 400)))

    let limit = max(1, min(1000, parseInt(args["limit"], fallback: 200)))

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

      // Fetch incomplete reminders with due date in [start, end]
      var merged: [String: EKReminder] = [:]
      let group = DispatchGroup()

      group.enter()
      let predIncomplete = self.store.predicateForIncompleteReminders(
        withDueDateStarting: startDate,
        ending: endDate,
        calendars: calendars
      )
      self.store.fetchReminders(matching: predIncomplete) { reminders in
        for r in (reminders ?? []) {
          merged[r.calendarItemIdentifier] = r
        }
        group.leave()
      }

      if includeCompleted {
        group.enter()
        let predCompleted = self.store.predicateForCompletedReminders(
          withCompletionDateStarting: startDate,
          ending: endDate,
          calendars: calendars
        )
        self.store.fetchReminders(matching: predCompleted) { reminders in
          for r in (reminders ?? []) {
            merged[r.calendarItemIdentifier] = r
          }
          group.leave()
        }
      }

      if includeUndated {
        group.enter()
        let predAllIncomplete = self.store.predicateForIncompleteReminders(
          withDueDateStarting: nil,
          ending: nil,
          calendars: calendars
        )
        self.store.fetchReminders(matching: predAllIncomplete) { reminders in
          for r in (reminders ?? []) {
            if r.dueDateComponents == nil {
              merged[r.calendarItemIdentifier] = r
            }
          }
          group.leave()
        }
      }

      group.notify(queue: .global()) {
        var items: [[String: Any]] = []

        for r in merged.values {
          // If completed are excluded, drop them.
          if !includeCompleted && r.isCompleted {
            continue
          }

          // Enforce date window: we use due date if present; otherwise it's undated (already filtered by includeUndated).
          var dueDate: Date? = nil
          if let comps = r.dueDateComponents {
            dueDate = Calendar.current.date(from: comps)
          }
          if let d = dueDate {
            if d < startDate || d > endDate {
              continue
            }
          } else {
            if !includeUndated {
              continue
            }
          }

          items.append(self.reminderToMap(r, includeNotes: includeNotes, notesMaxLen: notesMaxLen))
        }

        // Sort by due date (undated at the end).
        items.sort { a, b in
          let aDue = a["dueIso"] as? String
          let bDue = b["dueIso"] as? String
          if aDue == nil && bDue == nil {
            return (a["title"] as? String ?? "") < (b["title"] as? String ?? "")
          }
          if aDue == nil { return false }
          if bDue == nil { return true }
          return aDue! < bDue!
        }

        let truncated = items.count > limit
        if truncated {
          items = Array(items.prefix(limit))
        }

        result([
          "startIso": self.isoString(startDate),
          "endIso": self.isoString(endDate),
          "count": items.count,
          "truncated": truncated,
          "reminders": items
        ])
      }
    }
  }

  private func handleGet(args: [String: Any]?, result: @escaping FlutterResult) {
    guard let args = args else {
      result(FlutterError(code: "bad_args", message: "Missing arguments", details: nil))
      return
    }

    let reminderId = (args["reminderId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if reminderId.isEmpty {
      result(FlutterError(code: "bad_args", message: "reminderId is required", details: nil))
      return
    }

    let includeNotes = parseBool(args["includeNotes"], fallback: false)
    let notesMaxLen = max(0, min(8000, parseInt(args["notesMaxLen"], fallback: 400)))

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

      result(["reminder": self.reminderToMap(item, includeNotes: includeNotes, notesMaxLen: notesMaxLen)])
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

    let notesRaw = (args["notes"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let dueIso = (args["dueIso"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    let priority = parseInt(args["priority"], fallback: 0)
    let urlRaw = (args["url"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    let alarmMinutes = parseAlarmMinutesArray(args["alarmMinutes"]) ?? []

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

      if !notesRaw.isEmpty {
        reminder.notes = notesRaw
      }

      if priority != 0 {
        reminder.priority = max(0, min(9, priority))
      }

      if !urlRaw.isEmpty, let url = URL(string: urlRaw) {
        reminder.url = url
      }

      var dueDate: Date? = nil
      if !dueIso.isEmpty, let d = self.parseIso(dueIso) {
        dueDate = d
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
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

      if !alarmMinutes.isEmpty {
        guard let dd = dueDate else {
          result(FlutterError(code: "bad_args", message: "alarmMinutes requires dueIso", details: nil))
          return
        }
        self.applyReminderAlarms(reminder: reminder, dueDate: dd, alarmMinutes: alarmMinutes)
      }

      do {
        try self.store.save(reminder, commit: true)
        result([
          "id": reminder.calendarItemIdentifier,
          "title": reminder.title,
          "listId": reminder.calendar.calendarIdentifier
        ])
      } catch {
        result(FlutterError(code: "save_failed", message: "Failed to save reminder: \(error.localizedDescription)", details: nil))
      }
    }
  }

  private func handleUpdate(args: [String: Any]?, result: @escaping FlutterResult) {
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

      if let rawTitle = args["title"] as? String {
        let t = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        item.title = t
      }

      if let rawNotes = args["notes"] as? String {
        let n = rawNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes = n.isEmpty ? nil : n
      }

      if let rawListId = args["listId"] as? String {
        let lid = rawListId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lid.isEmpty, let cal = self.store.calendar(withIdentifier: lid) {
          item.calendar = cal
        }
      }

      if args.keys.contains("priority") {
        let p = self.parseInt(args["priority"], fallback: 0)
        item.priority = max(0, min(9, p))
      }

      if let rawUrl = args["url"] as? String {
        let u = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty {
          item.url = nil
        } else if let url = URL(string: u) {
          item.url = url
        }
      }

      var dueDate: Date? = nil
      let clearDue = self.parseBool(args["clearDue"], fallback: false)
      if clearDue {
        item.dueDateComponents = nil
      } else if let rawDue = args["dueIso"] as? String {
        let s = rawDue.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty {
          item.dueDateComponents = nil
        } else if let d = self.parseIso(s) {
          dueDate = d
          let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
          item.dueDateComponents = comps
        }
      }

      let clearAlarms = self.parseBool(args["clearAlarms"], fallback: false)
      if clearAlarms {
        item.alarms = nil
      }

      if let mins = self.parseAlarmMinutesArray(args["alarmMinutes"]) {
        if mins.isEmpty {
          item.alarms = nil
        } else {
          // Determine dueDate if not already parsed.
          if dueDate == nil, let comps = item.dueDateComponents {
            dueDate = Calendar.current.date(from: comps)
          }
          guard let dd = dueDate else {
            result(FlutterError(code: "bad_args", message: "alarmMinutes requires dueIso (or existing due date)", details: nil))
            return
          }
          self.applyReminderAlarms(reminder: item, dueDate: dd, alarmMinutes: mins)
        }
      }

      do {
        try self.store.save(item, commit: true)
        result(["ok": true, "id": reminderId])
      } catch {
        result(FlutterError(code: "save_failed", message: "Failed to update reminder: \(error.localizedDescription)", details: nil))
      }
    }
  }

  private func handleComplete(args: [String: Any]?, completed: Bool, result: @escaping FlutterResult) {
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

      item.isCompleted = completed
      item.completionDate = completed ? Date() : nil

      do {
        try self.store.save(item, commit: true)
        result(["ok": true, "id": reminderId, "completed": completed])
      } catch {
        result(FlutterError(code: "save_failed", message: "Failed to update reminder completion: \(error.localizedDescription)", details: nil))
      }
    }
  }
}
