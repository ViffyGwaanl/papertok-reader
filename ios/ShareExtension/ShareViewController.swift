//
//  ShareViewController.swift
//  shareExtension
//
//  Created by Anx c on 5/21/25.
//

import UIKit
import Social
import MobileCoreServices
import Photos
import Intents
import Contacts
import UniformTypeIdentifiers
import share_handler_ios_models

/// A namespaced Share Sheet controller.
///
/// Why vendored?
/// - Upstream `ShareHandlerIosViewController` writes attachments into App Group
///   container *root*, making cleanup unsafe.
/// - We write into: `<AppGroup>/share_handler/inbox/<eventId>/files/<filename>`
///   and keep the UserDefaults `ShareKey` payload unchanged for compatibility.
@available(iOS 14.0, *)
@available(iOSApplicationExtension 14.0, *)
class PapertokShareHandlerViewController: UIViewController {
  static var hostAppBundleIdentifier = ""
  static var appGroupId = ""

  private let sharedKey = "ShareKey"

  private var sharedText: [String] = []
  private var sharedAttachments: [SharedAttachment] = []
  private var fileNameCounter: [String: Int] = [:]

  private let imageContentType = UTType.image.identifier
  private let movieContentType = UTType.movie.identifier
  private let textContentType = UTType.text.identifier
  private let urlContentType = UTType.url.identifier
  private let fileURLType = UTType.fileURL.identifier
  private let dataContentType = UTType.data.identifier

  private lazy var eventId: String = UUID().uuidString
  private lazy var createdAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

  private lazy var userDefaults: UserDefaults = {
    return UserDefaults(suiteName: PapertokShareHandlerViewController.appGroupId)!
  }()

  override func viewDidLoad() {
    super.viewDidLoad()

    loadIds()

    Task {
      await handleInputItems()
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }

  private func loadIds() {
    let shareExtensionBundleIdentifier = Bundle.main.bundleIdentifier ?? ""

    // Convert ShareExtension id to host app id: drop the last component.
    if let lastDot = shareExtensionBundleIdentifier.lastIndex(of: ".") {
      PapertokShareHandlerViewController.hostAppBundleIdentifier =
        String(shareExtensionBundleIdentifier[..<lastDot])
    } else {
      PapertokShareHandlerViewController.hostAppBundleIdentifier =
        shareExtensionBundleIdentifier
    }

    // AppGroupId from Info.plist build setting or fallback.
    let configured =
      (Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String) ?? ""
    let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      PapertokShareHandlerViewController.appGroupId = trimmed
    } else {
      PapertokShareHandlerViewController.appGroupId =
        "group.\(PapertokShareHandlerViewController.hostAppBundleIdentifier)"
    }
  }

  private func inboxEventDir() throws -> URL {
    let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: PapertokShareHandlerViewController.appGroupId
    )!

    let dir = container
      .appendingPathComponent("share_handler", isDirectory: true)
      .appendingPathComponent("inbox", isDirectory: true)
      .appendingPathComponent(eventId, isDirectory: true)

    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // Best-effort meta.
    let metaUrl = dir.appendingPathComponent("meta.json")
    if !FileManager.default.fileExists(atPath: metaUrl.path) {
      let meta: [String: Any] = [
        "eventId": eventId,
        "createdAtMs": createdAtMs,
        "bundleId": Bundle.main.bundleIdentifier ?? "",
      ]
      if let data = try? JSONSerialization.data(withJSONObject: meta, options: []) {
        try? data.write(to: metaUrl, options: .atomic)
      }
    }

    return dir
  }

  private func newFileUrl(fileName: String) -> URL {
    let safeName = (fileName as NSString).lastPathComponent

    do {
      let base = try inboxEventDir()
      let filesDir = base.appendingPathComponent("files", isDirectory: true)
      try? FileManager.default.createDirectory(
        at: filesDir,
        withIntermediateDirectories: true
      )
      return filesDir.appendingPathComponent(safeName)
    } catch {
      // Fallback to container root (should be rare).
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: PapertokShareHandlerViewController.appGroupId
      )!
      return container.appendingPathComponent(safeName)
    }
  }

  private func handleInputItems() async {
    guard let item = extensionContext?.inputItems.first as? NSExtensionItem else {
      redirectToHostApp()
      return
    }

    // Some share sources (Safari/Chrome) provide richer metadata here.
    if let t = item.attributedTitle?.string {
      let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
      if !s.isEmpty, !sharedText.contains(s) {
        sharedText.append(s)
      }
    }
    if let t = item.attributedContentText?.string {
      let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
      if !s.isEmpty, !sharedText.contains(s) {
        sharedText.append(s)
      }
    }

    let providers = item.attachments ?? []
    for (index, provider) in providers.enumerated() {
      do {
        if provider.hasItemConformingToTypeIdentifier(imageContentType) {
          try await handleImages(attachment: provider, index: index)
          continue
        }
        if provider.hasItemConformingToTypeIdentifier(movieContentType) {
          try await handleVideos(attachment: provider, index: index)
          continue
        }
        if provider.hasItemConformingToTypeIdentifier(fileURLType) {
          try await handleFiles(attachment: provider, index: index)
          continue
        }

        // Web shares (Safari/Chrome) may expose multiple representations on the
        // SAME provider (e.g. url + text). Capture both.
        if provider.hasItemConformingToTypeIdentifier(textContentType) {
          try await handleText(attachment: provider, index: index)
        }
        if provider.hasItemConformingToTypeIdentifier(urlContentType) {
          try await handleUrl(attachment: provider, index: index)
        }
        if provider.hasItemConformingToTypeIdentifier(dataContentType) {
          try await handleData(attachment: provider, index: index)
        }
      } catch {
        // Best-effort: ignore per-item failure.
      }
    }

    redirectToHostApp()
  }

  private func handleText(attachment: NSItemProvider, index: Int) async throws {
    let data = try await attachment.loadItem(forTypeIdentifier: textContentType, options: nil)

    if let item = data as? String {
      sharedText.append(item)
      return
    }

    if let d = data as? Data {
      do {
        let contacts = try CNContactVCardSerialization.contacts(with: d)
        for contact in contacts {
          let data = try CNContactVCardSerialization.data(with: [contact])
          let str = String(data: data, encoding: .utf8) ?? ""
          if !str.isEmpty { sharedText.append(str) }
        }
      } catch {
        // ignore
      }
    }
  }

  private func handleUrl(attachment: NSItemProvider, index: Int) async throws {
    let data = try await attachment.loadItem(forTypeIdentifier: urlContentType, options: nil)

    if let url = data as? URL {
      let s = url.absoluteString
      if !s.isEmpty, !sharedText.contains(s) {
        sharedText.append(s)
      }
    }
  }

  private func handleImages(attachment: NSItemProvider, index: Int) async throws {
    let data = try await attachment.loadItem(forTypeIdentifier: imageContentType, options: nil)

    var fileName: String?
    var imageData: Data?
    var sourceUrl: URL?

    if let url = data as? URL {
      fileName = getFileName(from: url, type: .image)
      sourceUrl = url
    } else if let d = data as? Data {
      fileName = UUID().uuidString + ".png"
      imageData = d
    } else if let image = data as? UIImage {
      fileName = UUID().uuidString + ".png"
      imageData = image.pngData()
    }

    guard let name = fileName else { return }

    let newUrl = newFileUrl(fileName: name)
    try? FileManager.default.removeItem(at: newUrl)

    var copied = false
    if let d = imageData {
      copied = FileManager.default.createFile(atPath: newUrl.path, contents: d)
    } else if let src = sourceUrl {
      copied = copyFile(at: src, to: newUrl)
    }

    if copied {
      // IMPORTANT: share_handler_platform_interface will Uri.decodeFull() this string.
      // Use a URL-encoded absoluteString to avoid "Illegal percent encoding" crashes.
      sharedAttachments.append(
        SharedAttachment(path: newUrl.absoluteString, type: .image)
      )
    }
  }

  private func handleVideos(attachment: NSItemProvider, index: Int) async throws {
    let data = try await attachment.loadItem(forTypeIdentifier: movieContentType, options: nil)
    if let url = data as? URL {
      let fileName = getFileName(from: url, type: .video)
      let newUrl = newFileUrl(fileName: fileName)
      let copied = copyFile(at: url, to: newUrl)
      if copied {
        sharedAttachments.append(
          SharedAttachment(path: newUrl.absoluteString, type: .video)
        )
      }
    }
  }

  private func handleFiles(attachment: NSItemProvider, index: Int) async throws {
    let data = try await attachment.loadItem(forTypeIdentifier: fileURLType, options: nil)
    if let url = data as? URL {
      let fileName = getFileName(from: url, type: .file)
      let newUrl = newFileUrl(fileName: fileName)
      let copied = copyFile(at: url, to: newUrl)
      if copied {
        sharedAttachments.append(
          SharedAttachment(path: newUrl.absoluteString, type: .file)
        )
      }
    }
  }

  private func handleData(attachment: NSItemProvider, index: Int) async throws {
    let data = try await attachment.loadItem(forTypeIdentifier: dataContentType, options: nil)
    if let url = data as? URL {
      let fileName = getFileName(from: url, type: .file)
      let newUrl = newFileUrl(fileName: fileName)
      let copied = copyFile(at: url, to: newUrl)
      if copied {
        sharedAttachments.append(
          SharedAttachment(path: newUrl.absoluteString, type: .file)
        )
      }
    }
  }

  private func redirectToHostApp() {
    loadIds()

    let url = URL(
      string:
        "ShareMedia-\(PapertokShareHandlerViewController.hostAppBundleIdentifier)://\(PapertokShareHandlerViewController.hostAppBundleIdentifier)?key=\(sharedKey)"
    )

    var responder = self as UIResponder?
    let selectorOpenURL = sel_registerName("openURL:")

    let intent = self.extensionContext?.intent as? INSendMessageIntent

    let conversationIdentifier = intent?.conversationIdentifier
    let sender = intent?.sender
    let serviceName = intent?.serviceName
    let speakableGroupName = intent?.speakableGroupName

    let sharedMedia = SharedMedia(
      attachments: sharedAttachments,
      conversationIdentifier: conversationIdentifier,
      content: sharedText.joined(separator: "\n"),
      speakableGroupName: speakableGroupName?.spokenPhrase,
      serviceName: serviceName,
      senderIdentifier: sender?.contactIdentifier ?? sender?.customIdentifier,
      imageFilePath: nil
    )

    let json = sharedMedia.toJson()
    userDefaults.set(json, forKey: sharedKey)
    userDefaults.synchronize()

    while responder != nil {
      if let application = responder as? UIApplication, let u = url {
        if #available(iOS 18.0, *) {
          let _ = application.open(u, options: [:], completionHandler: nil)
        } else {
          let _ = application.perform(selectorOpenURL, with: u)
        }
      }
      responder = responder?.next
    }
  }

  // MARK: - Helpers

  private func copyFile(at src: URL, to dst: URL) -> Bool {
    do {
      if FileManager.default.fileExists(atPath: dst.path) {
        try FileManager.default.removeItem(at: dst)
      }
      try FileManager.default.copyItem(at: src, to: dst)
      return true
    } catch {
      return false
    }
  }

  private func getFileName(from url: URL, type: SharedAttachmentType) -> String {
    let base = url.lastPathComponent.isEmpty ? UUID().uuidString : url.lastPathComponent

    // Ensure extension.
    let ext = getExtension(from: url, type: type)
    var fileName = base
    if !ext.isEmpty && !fileName.lowercased().hasSuffix(".\(ext)") {
      fileName = "\(fileName).\(ext)"
    }

    // De-dup.
    if let count = fileNameCounter[fileName] {
      fileNameCounter[fileName] = count + 1
      let stem = (fileName as NSString).deletingPathExtension
      let e = (fileName as NSString).pathExtension
      if e.isEmpty {
        return "\(stem)_\(count + 1)"
      }
      return "\(stem)_\(count + 1).\(e)"
    }

    fileNameCounter[fileName] = 0
    return fileName
  }

  private func getExtension(from url: URL, type: SharedAttachmentType) -> String {
    let parts = url.lastPathComponent.components(separatedBy: ".")
    if parts.count > 1, let ex = parts.last, !ex.isEmpty {
      return ex
    }

    switch type {
    case .image:
      return "png"
    case .video:
      return "mp4"
    case .audio:
      return "m4a"
    case .file:
      return "bin"
    }
  }
}

class ShareViewController: PapertokShareHandlerViewController {}
