import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let remindersChannel = RemindersChannel()
  private let calendarEventKitChannel = CalendarEventKitChannel()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      remindersChannel.register(with: controller)
      calendarEventKitChannel.register(with: controller)
      PapertokPendingAskBridge.register(with: controller)
    }

    // Best-effort: prewarm a headless FlutterEngine for App Intents so the
    // Shortcuts action starts faster (iOS will still decide background limits).
    if #available(iOS 16.0, *) {
      Task.detached {
        await PapertokFlutterShortcuts.shared.prewarm()
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

/// Allows Flutter (host app) to consume a pending Shortcuts/AppIntent handoff.
///
/// We intentionally keep this native because AppIntents may persist payloads
/// in a dedicated UserDefaults suite that Flutter SharedPreferences does not
/// read from.
final class PapertokPendingAskBridge {
  private static let channelName = "papertok_reader/pending_ask"

  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "consume":
        if #available(iOS 16.0, *) {
          result(PapertokIntentPendingQueue.consume())
        } else {
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
