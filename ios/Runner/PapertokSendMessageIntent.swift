import AppIntents
import Flutter
import UIKit

@available(iOS 16.0, *)
struct PapertokSendMessageIntent: AppIntent {
  static var title: LocalizedStringResource = "\u{7ed9} Papertok \u{53d1}\u{9001}\u{56fe}\u{7247}\u{6d88}\u{606f}"

  static var description = IntentDescription(
    "\u{5411} Papertok Reader \u{7684} AI \u{53d1}\u{9001}\u{6587}\u{5b57}\u{4e0e}\u{56fe}\u{7247}\u{ff08}\u{6700}\u{591a} 4 \u{5f20}\u{ff09}\u{ff0c}\u{5e76}\u{8fd4}\u{56de}\u{56de}\u{590d}\u{5185}\u{5bb9}\u{3002}\n\n\u{8fd9}\u{4e2a}\u{52a8}\u{4f5c}\u{4f1a}\u{590d}\u{7528} App \u{5185}\u{73b0}\u{6709}\u{7684}\u{591a}\u{6a21}\u{6001} AI Chat \u{901a}\u{9053}\u{ff08}Flutter + LangChain\u{ff09}\u{ff0c}\u{4e0d}\u{4f1a}\u{91cd}\u{5199}\u{4e0a}\u{4f20}\u{6216}\u{8bf7}\u{6c42}\u{903b}\u{8f91}\u{3002}"
  )

  // Run in background by default (user can still choose to open the app).
  static var openAppWhenRun: Bool = false

  @Parameter(title: "\u{6587}\u{5b57}")
  var prompt: String = ""

  @Parameter(title: "\u{56fe}\u{7247}")
  var images: [IntentFile] = []

  @Parameter(title: "\u{8fd0}\u{884c}\u{65f6}\u{6253}\u{5f00} Papertok")
  var openApp: Bool?

  @Parameter(title: "\u{4f7f}\u{7528}\u{5f39}\u{7a97}\u{5c55}\u{793a}\u{56de}\u{590d}")
  var showDialog: Bool?

  static var parameterSummary: some ParameterSummary {
    Summary("\u{7ed9} Papertok \u{53d1}\u{9001} \(\.$prompt) \u{548c} \(\.$images)") {
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

    let dialogText = shouldShowDialog ? PapertokIntentUI.truncateForDialog(reply) : ""
    return .result(value: reply, dialog: IntentDialog(stringLiteral: dialogText))
  }
}

@available(iOS 16.0, *)
struct PapertokAppShortcutsProvider: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
        intent: PapertokSendMessageIntent(),
        phrases: [
          "\u{7ed9} Papertok \u{53d1}\u{9001}\u{56fe}\u{7247}\u{6d88}\u{606f}",
          "\u{7528} \(.applicationName) \u{53d1}\u{9001}\u{56fe}\u{7247}\u{6d88}\u{606f}",
          "\u{7528} \(.applicationName) \u{5206}\u{6790}\u{8fd9}\u{4e9b}\u{56fe}\u{7247}"
        ],
        shortTitle: "\u{53d1}\u{56fe}\u{95ee} Papertok",
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
    return String(s[..<idx]) + "\n\n\u{2026}"
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
        NSLocalizedDescriptionKey: "\u{6700}\u{591a}\u{53ea}\u{652f}\u{6301} \(maxCount) \u{5f20}\u{56fe}\u{7247}"
      ])
    }

    var out: [String] = []
    out.reserveCapacity(files.count)

    for f in files {
      // IntentFile can provide either a URL or data.
      let data: Data
      if let url = f.fileURL {
        data = try Data(contentsOf: url)
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
