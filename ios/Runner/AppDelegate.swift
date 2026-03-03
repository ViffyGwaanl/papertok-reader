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
