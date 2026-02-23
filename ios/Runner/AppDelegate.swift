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
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
