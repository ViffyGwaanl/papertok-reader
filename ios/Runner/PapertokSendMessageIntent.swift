import AppIntents
import Flutter
import UIKit

@available(iOS 16.0, *)
struct PapertokSendMessageIntent: AppIntent {
  static var title: LocalizedStringResource = "\u7ed9 Papertok \u53d1\u9001\u56fe\u7247\u6d88\u606f"

  static var description = IntentDescription(
    "\u5411 Papertok Reader \u7684 AI \u53d1\u9001\u6587\u5b57\u4e0e\u56fe\u7247\uff08\u6700\u591a 4 \u5f20\uff09\uff0c\u5e76\u8fd4\u56de\u56de\u590d\u5185\u5bb9\u3002\n\n\u8fd9\u4e2a\u52a8\u4f5c\u4f1a\u590d\u7528 App \u5185\u73b0\u6709\u7684\u591a\u6a21\u6001 AI Chat \u901a\u9053\uff08Flutter + LangChain\uff09\uff0c\u4e0d\u4f1a\u91cd\u5199\u4e0a\u4f20\u6216\u8bf7\u6c42\u903b\u8f91\u3002"
  )

  // Run in background by default (user can still choose to open the app).
  static var openAppWhenRun: Bool = false

  @Parameter(title: "\u6587\u5b57", default: "")
  var prompt: String

  @Parameter(title: "\u56fe\u7247")
  var images: [IntentFile]

  @Parameter(title: "\u8fd0\u884c\u65f6\u6253\u5f00 Papertok")
  var openApp: Bool?

  @Parameter(title: "\u4f7f\u7528\u5f39\u7a97\u5c55\u793a\u56de\u590d")
  var showDialog: Bool?

  static var parameterSummary: some ParameterSummary {
    Summary("\u7ed9 Papertok \u53d1\u9001 \(\.$prompt) \u548c \(\.$images)") {
      \.$openApp
      \.$showDialog
    }
  }

  func perform() async throws -> some IntentResult & ReturnsValue<String> {
    let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

    let shouldOpenApp = openApp ?? PapertokIntentDefaults.openAppDefault()
    let shouldShowDialog = showDialog ?? PapertokIntentDefaults.showDialogDefault()

    if shouldOpenApp {
      await PapertokIntentUI.openPapertokAppBestEffort()
    }

    let jpegB64 = try await PapertokIntentImageCodec.encodeToJpegBase64(
      files: images,
      maxCount: 4,
      maxPixel: 2048,
      quality: 0.86
    )

    let reply = try await PapertokFlutterShortcuts.shared.sendMessage(
      prompt: trimmedPrompt,
      imagesBase64: jpegB64
    )

    if shouldShowDialog {
      let dialogText = PapertokIntentUI.truncateForDialog(reply)
      return .result(value: reply, dialog: IntentDialog(stringLiteral: dialogText))
    }

    return .result(value: reply)
  }
}

@available(iOS 16.0, *)
struct PapertokAppShortcutsProvider: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    [
      AppShortcut(
        intent: PapertokSendMessageIntent(),
        phrases: [
          "\u7ed9 Papertok \u53d1\u9001\u56fe\u7247\u6d88\u606f",
          "\u7528 \(.applicationName) \u53d1\u9001\u56fe\u7247\u6d88\u606f",
          "\u7528 \(.applicationName) \u5206\u6790\u8fd9\u4e9b\u56fe\u7247"
        ],
        shortTitle: "\u53d1\u56fe\u95ee Papertok",
        systemImageName: "paperplane"
      )
    ]
  }
}

@available(iOS 16.0, *)
enum PapertokIntentDefaults {
  // These keys are stored by Flutter SharedPreferences.
  // Keep in sync with lib/config/shared_preference_provider.dart.
  private static let openAppKey = "shortcutsSendMessageOpenAppDefaultV1"
  private static let showDialogKey = "shortcutsSendMessageShowDialogDefaultV1"

  static func openAppDefault() -> Bool {
    return UserDefaults.standard.object(forKey: openAppKey) as? Bool ?? true
  }

  static func showDialogDefault() -> Bool {
    return UserDefaults.standard.object(forKey: showDialogKey) as? Bool ?? true
  }
}

@available(iOS 16.0, *)
enum PapertokIntentUI {
  static func truncateForDialog(_ s: String) -> String {
    // Keep the dialog readable. Shortcuts dialogs are not meant for huge text.
    let maxChars = 900
    if s.count <= maxChars { return s }
    let idx = s.index(s.startIndex, offsetBy: maxChars)
    return String(s[..<idx]) + "\n\n\u2026"
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
    if engine != nil && channel != nil {
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

    let channel = FlutterMethodChannel(
      name: "papertok_reader/shortcuts",
      binaryMessenger: engine.binaryMessenger
    )

    self.engine = engine
    self.channel = channel
  }

  func sendMessage(prompt: String, imagesBase64: [String]) async throws -> String {
    ensureEngine()

    guard let channel = channel else {
      throw NSError(domain: "PapertokShortcuts", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Flutter channel not ready"
      ])
    }

    let args: [String: Any] = [
      "prompt": prompt,
      "imagesBase64": imagesBase64
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
        NSLocalizedDescriptionKey: "\u6700\u591a\u53ea\u652f\u6301 \(maxCount) \u5f20\u56fe\u7247"
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
