import Flutter
import UIKit
import UniformTypeIdentifiers

final class BookmarkChannel: NSObject, UIDocumentPickerDelegate {
  private static let channelName = "ai.papertok.paperreader/bookmark"

  private var channel: FlutterMethodChannel?
  private weak var hostController: UIViewController?
  private var pendingPickResult: FlutterResult?
  private var activeScopes: [String: URL] = [:]

  func register(with controller: FlutterViewController) {
    self.hostController = controller
    let ch = FlutterMethodChannel(
      name: BookmarkChannel.channelName,
      binaryMessenger: controller.binaryMessenger
    )
    self.channel = ch
    ch.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickInPlace":
      pickInPlace(args: call.arguments as? [String: Any] ?? [:], result: result)
    case "resolveBookmark":
      resolveBookmark(args: call.arguments as? [String: Any] ?? [:], result: result)
    case "startAccess":
      startAccess(args: call.arguments as? [String: Any] ?? [:], result: result)
    case "stopAccess":
      stopAccess(args: call.arguments as? [String: Any] ?? [:], result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func pickInPlace(args: [String: Any], result: @escaping FlutterResult) {
    guard pendingPickResult == nil, let host = hostController else {
      result(FlutterError(code: "busy", message: "Picker already active", details: nil))
      return
    }
    let allowedExt = (args["allowedExt"] as? [String]) ?? ["pdf", "epub"]
    var types: [UTType] = []
    for e in allowedExt {
      if let t = UTType(filenameExtension: e) { types.append(t) }
    }
    if types.isEmpty { types = [UTType.pdf, UTType.epub] }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    pendingPickResult = result
    host.present(picker, animated: true, completion: nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController,
                      didPickDocumentsAt urls: [URL]) {
    let r = pendingPickResult
    pendingPickResult = nil
    guard let url = urls.first else { r?(nil); return }
    let started = url.startAccessingSecurityScopedResource()
    defer { if started { url.stopAccessingSecurityScopedResource() } }
    do {
      let blob = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      var size: Int64 = 0
      var mtime: Double = 0
      if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
        size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if let d = attrs[.modificationDate] as? Date { mtime = d.timeIntervalSince1970 }
      }
      r?([
        "bookmark": blob.base64EncodedString(),
        "name": url.lastPathComponent,
        "size": size,
        "mtime": mtime,
        "ext": url.pathExtension.lowercased(),
        "displayPath": url.path,
      ])
    } catch {
      r?(FlutterError(code: "bookmark_failed", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let r = pendingPickResult
    pendingPickResult = nil
    r?(nil)
  }

  private func resolveBookmark(args: [String: Any], result: @escaping FlutterResult) {
    guard let blobB64 = args["bookmark"] as? String,
          let blob = Data(base64Encoded: blobB64) else {
      result(FlutterError(code: "invalid_args", message: "bookmark missing", details: nil))
      return
    }
    var isStale: Bool = false
    do {
      let url = try URL(resolvingBookmarkData: blob, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
      var out: [String: Any] = ["path": url.path, "isStale": isStale]
      if isStale {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
          out["freshBookmark"] = fresh.base64EncodedString()
        }
      }
      result(out)
    } catch {
      result(["path": NSNull(), "isStale": false, "error": error.localizedDescription])
    }
  }

  private func startAccess(args: [String: Any], result: @escaping FlutterResult) {
    guard let blobB64 = args["bookmark"] as? String,
          let blob = Data(base64Encoded: blobB64) else {
      result(FlutterError(code: "invalid_args", message: "bookmark missing", details: nil))
      return
    }
    var isStale: Bool = false
    do {
      let url = try URL(resolvingBookmarkData: blob, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
      let ok = url.startAccessingSecurityScopedResource()
      if !ok {
        result(FlutterError(code: "access_denied", message: "startAccessingSecurityScopedResource failed", details: nil))
        return
      }
      let token = UUID().uuidString
      activeScopes[token] = url
      var out: [String: Any] = ["token": token, "path": url.path, "isStale": isStale]
      if isStale {
        if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
          out["freshBookmark"] = fresh.base64EncodedString()
        }
      }
      result(out)
    } catch {
      result(FlutterError(code: "resolve_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func stopAccess(args: [String: Any], result: @escaping FlutterResult) {
    guard let token = args["token"] as? String,
          let url = activeScopes[token] else {
      result(nil)
      return
    }
    url.stopAccessingSecurityScopedResource()
    activeScopes.removeValue(forKey: token)
    result(nil)
  }
}
