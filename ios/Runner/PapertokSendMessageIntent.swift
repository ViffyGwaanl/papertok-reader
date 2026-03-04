import AppIntents
import Flutter
import UIKit
import UniformTypeIdentifiers

@available(iOS 16.0, *)
struct PapertokSendMessageIntent: AppIntent {
  static var title: LocalizedStringResource = "给 Papertok 发送图片消息"

  static var description = IntentDescription(
    "向 Papertok Reader 的 AI 发送文字与图片（最多 4 张），并返回回复内容。\n\n这个动作会复用 App 内现有的多模态 AI Chat 通道（Flutter + LangChain），不会重写上传或请求逻辑。"
  )

  // Doubao-like UX: foreground the app immediately.
  static var openAppWhenRun: Bool = true

  @Parameter(title: "文字")
  var prompt: String?

  @Parameter(title: "图片")
  var images: [IntentFile]?

  @Parameter(title: "运行时打开 Papertok")
  var openApp: Bool?

  @Parameter(title: "使用弹窗展示回复")
  var showDialog: Bool?

  static var parameterSummary: some ParameterSummary {
    Summary("给 Papertok 发送 \(\.$prompt) 和 \(\.$images)") {
      \.$openApp
      \.$showDialog
    }
  }

  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let trimmedPrompt = (prompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let selectedImages = images ?? []

    if trimmedPrompt.isEmpty && selectedImages.isEmpty {
      throw NSError(domain: "PapertokShortcuts", code: 4, userInfo: [
        NSLocalizedDescriptionKey: "请输入文字或选择图片"
      ])
    }

    let shouldOpenApp = openApp ?? PapertokIntentDefaults.openAppDefault()
    let shouldShowDialog = showDialog ?? PapertokIntentDefaults.showDialogDefault()

    // Swift requires a single concrete underlying return type for opaque returns.
    var out: IntentResultContainer<String, Never, Never, IntentDialog> =
      .result(value: "", dialog: IntentDialog(stringLiteral: ""))

    if shouldOpenApp {
      // Persist request first (avoid a race where the app drains before enqueue finishes).
      try await PapertokIntentPendingQueue.enqueue(
        prompt: trimmedPrompt,
        images: selectedImages
      )

      // Then open the in-app AI chat UI.
      await PapertokIntentUI.openPapertokAskUiBestEffort()

      let value = "已在 Papertok 中开始分析。"
      out.value = value

      // Showing Shortcuts popups while also foregrounding the app is flaky.
      // The primary UX is in-app.
      out.dialog = nil
      return out
    }

    // Background best-effort mode: run the network call inside Shortcuts.
    let jpegB64 = try await PapertokIntentImageCodec.encodeToJpegBase64(
      files: selectedImages,
      maxCount: 4,
      maxPixel: 2048,
      quality: 0.86
    )

    let reply = try await PapertokFlutterShortcuts.shared.sendMessage(
      prompt: trimmedPrompt,
      imagesBase64: jpegB64,
      timeoutSeconds: PapertokIntentDefaults.timeoutSeconds()
    )

    out.value = reply
    out.dialog = shouldShowDialog
      ? IntentDialog(stringLiteral: PapertokIntentUI.truncateForDialog(reply))
      : nil
    return out
  }
}

@available(iOS 16.0, *)
struct PapertokAppShortcutsProvider: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: PapertokSendMessageIntent(),
      phrases: [
        "用 \(.applicationName) 给 Papertok 发送图片消息",
        "用 \(.applicationName) 发送图片消息",
        "用 \(.applicationName) 分析这些图片"
      ],
      shortTitle: "发图问 Papertok",
      systemImageName: "paperplane"
    )
  }
}

@available(iOS 16.0, *)
enum PapertokIntentDefaults {
  // These keys are stored by Flutter SharedPreferences.
  // Keep in sync with lib/config/shared_preference_provider.dart.
  private static let openAppKey = "shortcutsSendMessageOpenAppDefaultV1"
  private static let showDialogKey = "shortcutsSendMessageShowDialogDefaultV1"
  private static let timeoutSecKey = "shortcutsSendMessageTimeoutSecV1"

  static func openAppDefault() -> Bool {
    return UserDefaults.standard.object(forKey: openAppKey) as? Bool ?? true
  }

  static func showDialogDefault() -> Bool {
    return UserDefaults.standard.object(forKey: showDialogKey) as? Bool ?? true
  }

  static func timeoutSeconds() -> Int {
    let v = UserDefaults.standard.object(forKey: timeoutSecKey) as? Int ?? 25
    return max(5, min(180, v))
  }
}

@available(iOS 16.0, *)
enum PapertokIntentUI {
  static func truncateForDialog(_ s: String) -> String {
    let maxChars = 900
    if s.count <= maxChars { return s }
    let idx = s.index(s.startIndex, offsetBy: maxChars)
    return String(s[..<idx]) + "\n\n…"
  }

  static func openPapertokAskUiBestEffort() async {
    await MainActor.run {
      guard let url = URL(string: "paperreader://shortcuts/ask") else { return }
      UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
  }
}

@available(iOS 16.0, *)
enum PapertokIntentPendingQueue {
  // Keep in sync with lib/service/shortcuts/papertok_shortcuts_pending_queue.dart.
  private static let key = "shortcutsPendingAskV1"

  private static func appGroupId() -> String? {
    return Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String
  }

  private static func groupDefaults() -> UserDefaults? {
    guard let gid = appGroupId(), !gid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return UserDefaults(suiteName: gid)
  }

  private static func sharedBaseDir() -> URL? {
    guard let gid = appGroupId() else { return nil }
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: gid)
  }

  private static func sharedAskDir() -> URL? {
    guard let base = sharedBaseDir() else { return nil }
    let dir = base.appendingPathComponent("shortcuts_ask", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private static func sharedImagesDir() -> URL? {
    guard let askDir = sharedAskDir() else { return nil }
    let dir = askDir.appendingPathComponent("images", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  static func enqueue(prompt: String, images: [IntentFile]) async throws {
    var payload: [String: Any] = [
      "prompt": prompt,
      "createdAtMs": Int(Date().timeIntervalSince1970 * 1000)
    ]

    // Persist images into the App Group container so the host app can read them.
    let paths = try await PapertokIntentImageCodec.persistAsJpegFiles(
      files: images,
      dir: sharedImagesDir(),
      maxCount: 4,
      maxPixel: 2048,
      quality: 0.86
    )
    payload["imagePaths"] = paths

    let data = try JSONSerialization.data(withJSONObject: payload)
    let json = String(data: data, encoding: .utf8) ?? "{}"

    // Prefer App Group storage; also dual-write to standard defaults as a fallback.
    groupDefaults()?.set(json, forKey: key)
    UserDefaults.standard.set(json, forKey: key)

    // Write to a shared file so the host app can consume atomically.
    try? writePendingFile(json)
  }

  private static func pendingFileUrl() -> URL {
    if let askDir = sharedAskDir() {
      return askDir.appendingPathComponent("pending.json")
    }

    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("shortcuts_ask", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("pending.json")
  }

  private static func writePendingFile(_ json: String) throws {
    let url = pendingFileUrl()
    try json.data(using: .utf8)?.write(to: url, options: [.atomic])
  }

  private static func consumePendingFile() -> String? {
    let url = pendingFileUrl()
    guard let data = try? Data(contentsOf: url), !data.isEmpty else {
      return nil
    }
    try? FileManager.default.removeItem(at: url)
    return String(data: data, encoding: .utf8)
  }

  static func consume() -> String? {
    if let ud = groupDefaults(),
       let s = ud.string(forKey: key),
       !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      ud.removeObject(forKey: key)
      return s
    }

    if let s = UserDefaults.standard.string(forKey: key),
       !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      UserDefaults.standard.removeObject(forKey: key)
      return s
    }

    return consumePendingFile()
  }

}

@available(iOS 16.0, *)
actor PapertokFlutterShortcuts {
  static let shared = PapertokFlutterShortcuts()

  private var engine: FlutterEngine?
  private var channel: FlutterMethodChannel?

  func prewarm() async {
    ensureEngine()
  }

  private func ensureEngine() {
    if channel != nil {
      return
    }

    // Prefer the main Flutter engine when the app is already running.
    if let delegate = UIApplication.shared.delegate as? AppDelegate,
       let controller = delegate.window?.rootViewController as? FlutterViewController {
      self.engine = nil
      self.channel = FlutterMethodChannel(
        name: "papertok_reader/shortcuts",
        binaryMessenger: controller.binaryMessenger
      )
      return
    }

    let engine = FlutterEngine(
      name: "PapertokShortcutsEngine",
      project: nil,
      allowHeadlessExecution: true
    )

    engine.run(withEntrypoint: "shortcutsMain")
    GeneratedPluginRegistrant.register(with: engine)

    self.engine = engine
    self.channel = FlutterMethodChannel(
      name: "papertok_reader/shortcuts",
      binaryMessenger: engine.binaryMessenger
    )
  }

  func sendMessage(
    prompt: String,
    imagesBase64: [String],
    timeoutSeconds: Int
  ) async throws -> String {
    ensureEngine()

    guard let channel = channel else {
      throw NSError(domain: "PapertokShortcuts", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Flutter channel not ready"
      ])
    }

    try await waitForReady(channel: channel)

    let args: [String: Any] = [
      "prompt": prompt,
      "imagesBase64": imagesBase64,
      "timeoutSeconds": timeoutSeconds
    ]

    return try await withCheckedThrowingContinuation { cont in
      channel.invokeMethod("sendMessage", arguments: args) { result in
        if let err = result as? FlutterError {
          cont.resume(throwing: NSError(domain: "PapertokShortcuts", code: 2, userInfo: [
            NSLocalizedDescriptionKey: err.message ?? "FlutterError"
          ]))
          return
        }

        if let s = result as? String {
          cont.resume(returning: s)
          return
        }

        cont.resume(throwing: NSError(domain: "PapertokShortcuts", code: 3, userInfo: [
          NSLocalizedDescriptionKey: "Unexpected result type"
        ]))
      }
    }
  }

  private func waitForReady(channel: FlutterMethodChannel) async throws {
    for _ in 0..<6 {
      do {
        let ok: String = try await withCheckedThrowingContinuation { cont in
          channel.invokeMethod("ping", arguments: nil) { result in
            if let s = result as? String {
              cont.resume(returning: s)
              return
            }
            if let err = result as? FlutterError {
              cont.resume(throwing: NSError(domain: "PapertokShortcuts", code: 20, userInfo: [
                NSLocalizedDescriptionKey: err.message ?? "FlutterError"
              ]))
              return
            }
            cont.resume(throwing: NSError(domain: "PapertokShortcuts", code: 21, userInfo: [
              NSLocalizedDescriptionKey: "Ping failed"
            ]))
          }
        }

        if ok == "ok" { return }
      } catch {
        // ignore
      }

      try await Task.sleep(nanoseconds: 250_000_000)
    }
  }
}

@available(iOS 16.0, *)
enum PapertokIntentImageCodec {
  static func persistAsJpegFiles(
    files: [IntentFile],
    dir: URL?,
    maxCount: Int,
    maxPixel: CGFloat,
    quality: CGFloat
  ) async throws -> [String] {
    if files.count > maxCount {
      throw NSError(domain: "PapertokShortcuts", code: 10, userInfo: [
        NSLocalizedDescriptionKey: "最多只支持 \(maxCount) 张图片"
      ])
    }

    if files.isEmpty {
      return []
    }

    let baseDir: URL
    if let dir {
      baseDir = dir
    } else {
      baseDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("shortcuts_ask", isDirectory: true)
      try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    var out: [String] = []
    out.reserveCapacity(files.count)

    for f in files {
      let data = readIntentFileBestEffort(f)
      guard let img = UIImage(data: data) else {
        continue
      }

      let normalized = downsample(img, maxPixel: maxPixel)
      guard let jpeg = normalized.jpegData(compressionQuality: quality) else {
        continue
      }

      let dst = baseDir.appendingPathComponent(UUID().uuidString + ".jpg")
      try jpeg.write(to: dst, options: [.atomic])
      out.append(dst.path)
    }

    return out
  }

  static func encodeToJpegBase64(
    files: [IntentFile],
    maxCount: Int,
    maxPixel: CGFloat,
    quality: CGFloat
  ) async throws -> [String] {
    let paths = try await persistAsJpegFiles(
      files: files,
      maxCount: maxCount,
      maxPixel: maxPixel,
      quality: quality
    )

    var out: [String] = []
    out.reserveCapacity(paths.count)

    for p in paths {
      if let data = try? Data(contentsOf: URL(fileURLWithPath: p)) {
        out.append(data.base64EncodedString())
      }
    }

    return out
  }

  private static func readIntentFileBestEffort(_ f: IntentFile) -> Data {
    if let url = f.fileURL {
      let accessed = url.startAccessingSecurityScopedResource()
      defer {
        if accessed {
          url.stopAccessingSecurityScopedResource()
        }
      }

      if let data = try? Data(contentsOf: url) {
        return data
      }
    }

    return f.data
  }

  private static func downsample(_ image: UIImage, maxPixel: CGFloat) -> UIImage {
    let size = image.size
    let maxSide = max(size.width, size.height)
    if maxSide <= maxPixel {
      return image
    }

    let scale = maxPixel / maxSide
    let newSize = CGSize(width: size.width * scale, height: size.height * scale)

    UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
    image.draw(in: CGRect(origin: .zero, size: newSize))
    let out = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return out ?? image
  }
}
