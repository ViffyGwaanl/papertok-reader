import Foundation
import Flutter
import EventKit

final class CalendarEventKitChannel {
  private let store = EKEventStore()

  func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "ai.papertok.paperreader/calendar_eventkit",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "Calendar bridge unavailable", details: nil))
        return
      }

      switch call.method {
      case "listCalendars":
        self.handleListCalendars(result: result)
      case "listEvents":
        self.handleListEvents(args: call.arguments as? [String: Any], result: result)
      case "getEvent":
        self.handleGetEvent(args: call.arguments as? [String: Any], result: result)
      case "createEvent":
        self.handleCreateEvent(args: call.arguments as? [String: Any], result: result)
      case "updateEvent":
        self.handleUpdateEvent(args: call.arguments as? [String: Any], result: result)
      case "deleteEvent":
        self.handleDeleteEvent(args: call.arguments as? [String: Any], result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Helpers

  private func requestAccessIfNeeded(completion: @escaping (Bool, Error?) -> Void) {
    store.requestAccess(to: .event) { granted, error in
      completion(granted, error)
    }
  }

  private func parseIso(_ raw: String) -> Date? {
    let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { return nil }

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

  private func parseInt(_ raw: Any?, fallback: Int) -> Int {
    if let n = raw as? NSNumber { return n.intValue }
    if let s = raw as? String, let n = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return n }
    return fallback
  }

  private func parseBool(_ raw: Any?, fallback: Bool) -> Bool {
    if let b = raw as? Bool { return b }
    let s = (raw as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if s == "true" { return true }
    if s == "false" { return false }
    return fallback
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

  private func buildAlarmsForEvent(startDate: Date, alarmMinutes: [Int]) -> [EKAlarm] {
    return alarmMinutes
      .map { $0 }
      .filter { $0 >= 0 && $0 <= 60 * 24 * 365 }
      .map { minutes in
        // For events, relativeOffset is relative to event start.
        return EKAlarm(relativeOffset: TimeInterval(-minutes * 60))
      }
  }

  private func alarmMinutesFromEvent(_ event: EKEvent) -> [Int] {
    guard let alarms = event.alarms, !alarms.isEmpty else { return [] }

    var mins: [Int] = []
    for a in alarms {
      if a.relativeOffset != 0 {
        let m = Int(round((-a.relativeOffset) / 60.0))
        if m >= 0 { mins.append(m) }
        continue
      }
      if let abs = a.absoluteDate {
        let delta = event.startDate.timeIntervalSince(abs)
        let m = Int(round(delta / 60.0))
        if m >= 0 { mins.append(m) }
      }
    }

    // Stable output.
    mins = Array(Set(mins))
    mins.sort()
    return mins
  }

  private func parseInstanceId(_ raw: String) -> (eventId: String, startMillis: Int64?) {
    let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { return ("", nil) }
    if let at = s.firstIndex(of: "@") {
      let id = String(s[..<at])
      let suffix = String(s[s.index(after: at)...])
      if let ms = Int64(suffix) {
        return (id, ms)
      }
      return (id, nil)
    }
    return (s, nil)
  }

  private func findEvent(eventId: String, startMillis: Int64?) -> EKEvent? {
    if let startMillis = startMillis {
      let start = Date(timeIntervalSince1970: TimeInterval(startMillis) / 1000.0)
      let windowStart = start.addingTimeInterval(-48 * 3600)
      let windowEnd = start.addingTimeInterval(48 * 3600)
      let pred = store.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: nil)
      let events = store.events(matching: pred)
      let target = events.first { e in
        guard let eid = e.eventIdentifier else { return false }
        if eid != eventId { return false }
        let ms = Int64(e.startDate.timeIntervalSince1970 * 1000)
        return ms == startMillis
      }
      if let t = target { return t }
    }

    return store.event(withIdentifier: eventId)
  }

  private func eventToMap(
    _ event: EKEvent,
    includeDescription: Bool,
    includeAlarms: Bool
  ) -> [String: Any] {
    let startMillis = Int64(event.startDate.timeIntervalSince1970 * 1000)
    let eventId = event.eventIdentifier ?? ""

    let instanceId: String
    if event.hasRecurrenceRules {
      instanceId = "\(eventId)@\(startMillis)"
    } else {
      instanceId = eventId
    }

    var map: [String: Any] = [
      "eventId": eventId,
      "instanceId": instanceId,
      "calendarId": event.calendar.calendarIdentifier,
      "title": event.title ?? "",
      "allDay": event.isAllDay,
      "isRecurring": event.hasRecurrenceRules,
      "startIso": isoString(event.startDate),
      "endIso": isoString(event.endDate)
    ]

    if let location = event.location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      map["location"] = location
    }

    if includeDescription, let notes = event.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      map["description"] = notes
    }

    if includeAlarms {
      let mins = alarmMinutesFromEvent(event)
      if !mins.isEmpty {
        map["alarmMinutes"] = mins
      }
    }

    return map
  }

  private func parseRecurrenceRule(_ raw: Any?) -> EKRecurrenceRule? {
    guard let obj = raw as? [String: Any] else { return nil }
    let freqRaw = (obj["frequency"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if freqRaw.isEmpty { return nil }

    let frequency: EKRecurrenceFrequency
    switch freqRaw {
    case "daily": frequency = .daily
    case "weekly": frequency = .weekly
    case "monthly": frequency = .monthly
    case "yearly": frequency = .yearly
    default:
      return nil
    }

    let interval = max(1, min(365, parseInt(obj["interval"], fallback: 1)))

    var recurrenceEnd: EKRecurrenceEnd? = nil
    if let countAny = obj["count"], let count = Int((countAny as? NSNumber)?.stringValue ?? (countAny as? String ?? "")) {
      if count > 0 {
        recurrenceEnd = EKRecurrenceEnd(occurrenceCount: count)
      }
    }
    if recurrenceEnd == nil, let untilIso = obj["untilIso"] as? String, let until = parseIso(untilIso) {
      recurrenceEnd = EKRecurrenceEnd(end: until)
    }

    return EKRecurrenceRule(recurrenceWith: frequency, interval: interval, end: recurrenceEnd)
  }

  // MARK: - Handlers

  private func handleListCalendars(result: @escaping FlutterResult) {
    requestAccessIfNeeded { granted, error in
      if let error = error {
        result(FlutterError(code: "permission", message: "Permission error: \(error.localizedDescription)", details: nil))
        return
      }
      if !granted {
        result(FlutterError(code: "permissionDenied", message: "Calendar permission denied", details: nil))
        return
      }

      let cals = self.store.calendars(for: .event)
      let items: [[String: Any]] = cals.map { cal in
        [
          "id": cal.calendarIdentifier,
          "name": cal.title,
          "readOnly": !cal.allowsContentModifications
        ]
      }

      result(["calendars": items])
    }
  }

  private func handleListEvents(args: [String: Any]?, result: @escaping FlutterResult) {
    let args = args ?? [:]

    let startIso = (args["startIso"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let endIso = (args["endIso"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    let startDate = parseIso(startIso) ?? Date()
    let days = max(1, min(60, parseInt(args["days"], fallback: 7)))
    let endDate = parseIso(endIso) ?? startDate.addingTimeInterval(TimeInterval(days * 24 * 3600))

    let maxResults = max(1, min(200, parseInt(args["maxResults"], fallback: 50)))
    let includeDescription = parseBool(args["includeDescription"], fallback: false)
    let includeAlarms = parseBool(args["includeAlarms"], fallback: false)

    let calendarIds = (args["calendarIds"] as? [Any] ?? [])
      .compactMap { $0 as? String }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    requestAccessIfNeeded { granted, error in
      if let error = error {
        result(FlutterError(code: "permission", message: "Permission error: \(error.localizedDescription)", details: nil))
        return
      }
      if !granted {
        result(FlutterError(code: "permissionDenied", message: "Calendar permission denied", details: nil))
        return
      }

      let calendars: [EKCalendar]?
      if calendarIds.isEmpty {
        calendars = nil
      } else {
        calendars = calendarIds.compactMap { self.store.calendar(withIdentifier: $0) }
      }

      let predicate = self.store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
      var events = self.store.events(matching: predicate)
      events.sort { $0.startDate < $1.startDate }

      let truncated = events.count > maxResults
      if truncated {
        events = Array(events.prefix(maxResults))
      }

      let mapped = events.map { self.eventToMap($0, includeDescription: includeDescription, includeAlarms: includeAlarms) }

      result([
        "startIso": self.isoString(startDate),
        "endIso": self.isoString(endDate),
        "count": mapped.count,
        "truncated": truncated,
        "events": mapped
      ])
    }
  }

  private func handleGetEvent(args: [String: Any]?, result: @escaping FlutterResult) {
    guard let args = args else {
      result(FlutterError(code: "bad_args", message: "Missing arguments", details: nil))
      return
    }

    let idRaw = (args["instanceId"] as? String ?? args["eventId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if idRaw.isEmpty {
      result(FlutterError(code: "bad_args", message: "eventId or instanceId is required", details: nil))
      return
    }

    let includeDescription = parseBool(args["includeDescription"], fallback: true)
    let includeAlarms = parseBool(args["includeAlarms"], fallback: true)

    requestAccessIfNeeded { granted, error in
      if let error = error {
        result(FlutterError(code: "permission", message: "Permission error: \(error.localizedDescription)", details: nil))
        return
      }
      if !granted {
        result(FlutterError(code: "permissionDenied", message: "Calendar permission denied", details: nil))
        return
      }

      let parsed = self.parseInstanceId(idRaw)
      let event = self.findEvent(eventId: parsed.eventId, startMillis: parsed.startMillis)
      guard let event = event else {
        result(FlutterError(code: "not_found", message: "Event not found", details: nil))
        return
      }

      result(["event": self.eventToMap(event, includeDescription: includeDescription, includeAlarms: includeAlarms)])
    }
  }

  private func handleCreateEvent(args: [String: Any]?, result: @escaping FlutterResult) {
    guard let args = args else {
      result(FlutterError(code: "bad_args", message: "Missing arguments", details: nil))
      return
    }

    let title = (args["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if title.isEmpty {
      result(FlutterError(code: "bad_args", message: "title is required", details: nil))
      return
    }

    let startIso = (args["startIso"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let endIso = (args["endIso"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard let startDate = parseIso(startIso), let endDate = parseIso(endIso) else {
      result(FlutterError(code: "bad_args", message: "startIso/endIso must be valid ISO-8601", details: nil))
      return
    }

    let isAllDay = parseBool(args["isAllDay"], fallback: false)
    let location = (args["location"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let description = (args["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let timeZoneId = (args["timeZone"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    let alarmMinutes = parseAlarmMinutesArray(args["alarmMinutes"]) ?? []
    let recurrence = parseRecurrenceRule(args["recurrence"])

    let desiredCalendarId = (args["calendarId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    requestAccessIfNeeded { granted, error in
      if let error = error {
        result(FlutterError(code: "permission", message: "Permission error: \(error.localizedDescription)", details: nil))
        return
      }
      if !granted {
        result(FlutterError(code: "permissionDenied", message: "Calendar permission denied", details: nil))
        return
      }

      let event = EKEvent(eventStore: self.store)
      event.title = title
      event.startDate = startDate
      event.endDate = endDate
      event.isAllDay = isAllDay

      if !location.isEmpty { event.location = location }
      if !description.isEmpty { event.notes = description }

      if isAllDay {
        event.timeZone = nil
      } else if !timeZoneId.isEmpty, let tz = TimeZone(identifier: timeZoneId) {
        event.timeZone = tz
      }

      if !desiredCalendarId.isEmpty, let cal = self.store.calendar(withIdentifier: desiredCalendarId) {
        event.calendar = cal
      } else if let def = self.store.defaultCalendarForNewEvents {
        event.calendar = def
      } else {
        let calendars = self.store.calendars(for: .event)
        let writable = calendars.first { $0.allowsContentModifications }
        if let w = writable {
          event.calendar = w
        } else if let first = calendars.first {
          event.calendar = first
        }
      }

      if !alarmMinutes.isEmpty {
        event.alarms = self.buildAlarmsForEvent(startDate: startDate, alarmMinutes: alarmMinutes)
      }

      if let recurrence = recurrence {
        event.recurrenceRules = [recurrence]
      }

      do {
        try self.store.save(event, span: .thisEvent)
        var mapped = self.eventToMap(event, includeDescription: false, includeAlarms: true)
        mapped["ok"] = true
        result(mapped)
      } catch {
        result(FlutterError(code: "save_failed", message: "Failed to create event: \(error.localizedDescription)", details: nil))
      }
    }
  }

  private func handleUpdateEvent(args: [String: Any]?, result: @escaping FlutterResult) {
    guard let args = args else {
      result(FlutterError(code: "bad_args", message: "Missing arguments", details: nil))
      return
    }

    let idRaw = (args["instanceId"] as? String ?? args["eventId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if idRaw.isEmpty {
      result(FlutterError(code: "bad_args", message: "eventId or instanceId is required", details: nil))
      return
    }

    let spanRaw = (args["span"] as? String ?? "thisEvent").trimmingCharacters(in: .whitespacesAndNewlines)

    requestAccessIfNeeded { granted, error in
      if let error = error {
        result(FlutterError(code: "permission", message: "Permission error: \(error.localizedDescription)", details: nil))
        return
      }
      if !granted {
        result(FlutterError(code: "permissionDenied", message: "Calendar permission denied", details: nil))
        return
      }

      let parsed = self.parseInstanceId(idRaw)
      guard let event = self.findEvent(eventId: parsed.eventId, startMillis: parsed.startMillis) else {
        result(FlutterError(code: "not_found", message: "Event not found", details: nil))
        return
      }

      // Apply updates.
      if let rawTitle = args["title"] as? String {
        event.title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      }

      if let rawDesc = args["description"] as? String {
        let d = rawDesc.trimmingCharacters(in: .whitespacesAndNewlines)
        event.notes = d.isEmpty ? nil : d
      }

      if let rawLocation = args["location"] as? String {
        let l = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        event.location = l.isEmpty ? nil : l
      }

      if let rawAllDay = args["isAllDay"] {
        event.isAllDay = self.parseBool(rawAllDay, fallback: event.isAllDay)
      }

      if let rawStart = args["startIso"] as? String, let d = self.parseIso(rawStart) {
        event.startDate = d
      }
      if let rawEnd = args["endIso"] as? String, let d = self.parseIso(rawEnd) {
        event.endDate = d
      }

      let effectiveIsAllDay = event.isAllDay
      if effectiveIsAllDay {
        event.timeZone = nil
      } else if let rawTz = args["timeZone"] as? String {
        let tzId = rawTz.trimmingCharacters(in: .whitespacesAndNewlines)
        if tzId.isEmpty {
          // ignore
        } else if let tz = TimeZone(identifier: tzId) {
          event.timeZone = tz
        }
      }

      if let rawCalId = args["calendarId"] as? String {
        let calId = rawCalId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !calId.isEmpty, let cal = self.store.calendar(withIdentifier: calId) {
          event.calendar = cal
        }
      }

      let clearAlarms = self.parseBool(args["clearAlarms"], fallback: false)
      if clearAlarms {
        event.alarms = nil
      }

      if let mins = self.parseAlarmMinutesArray(args["alarmMinutes"]) {
        if mins.isEmpty {
          event.alarms = nil
        } else {
          event.alarms = self.buildAlarmsForEvent(startDate: event.startDate, alarmMinutes: mins)
        }
      }

      let clearRecurrence = self.parseBool(args["clearRecurrence"], fallback: false)
      if clearRecurrence {
        event.recurrenceRules = nil
      }

      if let rr = self.parseRecurrenceRule(args["recurrence"]) {
        event.recurrenceRules = [rr]
      }

      let span: EKSpan
      switch spanRaw.lowercased() {
      case "futureevents", "future":
        span = .futureEvents
      case "allevents", "all":
        span = .futureEvents
      default:
        span = .thisEvent
      }

      do {
        try self.store.save(event, span: span)
        result(["ok": true, "eventId": parsed.eventId, "span": spanRaw])
      } catch {
        result(FlutterError(code: "save_failed", message: "Failed to update event: \(error.localizedDescription)", details: nil))
      }
    }
  }

  private func handleDeleteEvent(args: [String: Any]?, result: @escaping FlutterResult) {
    guard let args = args else {
      result(FlutterError(code: "bad_args", message: "Missing arguments", details: nil))
      return
    }

    let idRaw = (args["instanceId"] as? String ?? args["eventId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if idRaw.isEmpty {
      result(FlutterError(code: "bad_args", message: "eventId or instanceId is required", details: nil))
      return
    }

    let spanRaw = (args["span"] as? String ?? "thisEvent").trimmingCharacters(in: .whitespacesAndNewlines)

    requestAccessIfNeeded { granted, error in
      if let error = error {
        result(FlutterError(code: "permission", message: "Permission error: \(error.localizedDescription)", details: nil))
        return
      }
      if !granted {
        result(FlutterError(code: "permissionDenied", message: "Calendar permission denied", details: nil))
        return
      }

      let parsed = self.parseInstanceId(idRaw)
      guard let event = self.findEvent(eventId: parsed.eventId, startMillis: parsed.startMillis) else {
        result(FlutterError(code: "not_found", message: "Event not found", details: nil))
        return
      }

      let span: EKSpan
      switch spanRaw.lowercased() {
      case "futureevents", "future":
        span = .futureEvents
      case "allevents", "all":
        span = .futureEvents
      default:
        span = .thisEvent
      }

      do {
        try self.store.remove(event, span: span)
        result(["ok": true, "eventId": parsed.eventId, "span": spanRaw])
      } catch {
        result(FlutterError(code: "delete_failed", message: "Failed to delete event: \(error.localizedDescription)", details: nil))
      }
    }
  }
}
