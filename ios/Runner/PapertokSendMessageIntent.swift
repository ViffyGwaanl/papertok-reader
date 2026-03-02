import AppIntents
import Flutter
import UIKit

@available(iOS 16.0, *)
struct PapertokSendMessageIntent: AppIntent {
  static var title: LocalizedStringResource = "给 Papertok 发送图片消息"

  static var description = IntentDescription(
    "向 Papertok Reader 的 AI 发送文字与图片（最多 4 张），并返回回复内容。\n\n这个动作会复用 App 内现有的多模态 AI Chat 通道（Flutter + LangChain），不会重写上传或请求逻辑。"
  )

  // Run in background by default (user can still choose to open the app).
  static var openAppWhenRun: Bool = false

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

    let shouldOpenApp = openApp ?? PapertokIntentDefaults.openAppDefault()
    let shouldShowDialog = showDialog ?? PapertokIntentDefaults.showDialogDefault()

    if shouldOpenApp {
      await PapertokIntentUI.openPapertokAppBestEffort()
    }

    let selectedImages = images ?? []
    if trimmedPrompt.isEmpty && selectedImages.isEmpty {
      throw NSError(domain: "PapertokShortcuts", code: 4, userInfo: [
        NSLocalizedDescriptionKey: "请输入文字或选择图片"
      ])
    }

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

    // Swift requires a single concrete underlying return type for opaque returns.
    // Return an IntentResultContainer<..., IntentDialog> and set dialog=nil when disabled
    // to preserve the "no popup" semantics.
    var out: IntentResultContainer<String, Never, Never, IntentDialog> =
      .result(value: reply, dialog: IntentDialog(stringLiteral: ""))

    if shouldShowDialog {
      let dialogText = PapertokIntentUI.truncateForDialog(reply)
      out.dialog = IntentDialog(stringLiteral: dialogText)
    } else {
      out.dialog = nil
    }

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
    // Keep the dialog readable. Shortcuts dialogs are not meant for huge text.
    let maxChars = 900
    if s.count <= maxChars { return s }
    let idx = s.index(s.startIndex, offsetBy: maxChars)
    return String(s[..<idx]) + "\n\n…"
  }

  static func openPapertokAppBestEffort() async {
    // Best-effort: open the app via our URL scheme.
    //
    // We intentionally use a host/path that the Flutter deep link handler will
    // ignore, so this acts as a simple "bring app to foreground" request.
    await MainActor.run {
      guard let url = URL(string: "paperreader://app") else { return }
      UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
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

  /// Starts (or reuses) a headless FlutterEngine that exposes the shortcuts
  /// MethodChannel.
  private func ensureEngine() {
    if channel != nil {
      return
    }

    // Prefer the main Flutter engine when the app is already running.
    // This avoids the cold-start cost of spinning up a separate headless engine.
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

    // The Dart entrypoint is defined in lib/main.dart as `shortcutsMain`.
    engine.run(withEntrypoint: "shortcutsMain")

    // Make sure plugins (SharedPreferences, networking, etc.) work in this
    // engine as well.
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

    // Wait briefly for the Dart isolate to register the channel handler.
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
    // Retry ping for ~1.5s.
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
  static func encodeToJpegBase64(
    files: [IntentFile],
    maxCount: Int,
    maxPixel: CGFloat,
    quality: CGFloat
  ) async throws -> [String] {
    if files.count > maxCount {
      throw NSError(domain: "PapertokShortcuts", code: 10, userInfo: [
        NSLocalizedDescriptionKey: "最多只支持 \(maxCount) 张图片"
      ])
    }

    var out: [String] = []
    out.reserveCapacity(files.count)

    for f in files {
      // IntentFile can provide either a URL or in-memory data.
      //
      // When the file comes from the share sheet, it is commonly a security-
      // scoped URL. We must request access before reading it.
      let data: Data
      if let url = f.fileURL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
          if accessed {
            url.stopAccessingSecurityScopedResource()
          }
        }

        do {
          data = try Data(contentsOf: url)
        } catch {
          // Fallback: some inputs may provide in-memory data even when the URL
          // is not accessible.
          data = f.data
        }
      } else {
        data = f.data
      }

      guard let img = UIImage(data: data) else {
        continue
      }

      let normalized = downsample(img, maxPixel: maxPixel)
      guard let jpeg = normalized.jpegData(compressionQuality: quality) else {
        continue
      }

      out.append(jpeg.base64EncodedString())
    }

    return out
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
