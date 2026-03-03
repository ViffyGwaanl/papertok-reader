import Flutter
import UIKit

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
