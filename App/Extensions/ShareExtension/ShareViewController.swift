#if os(iOS)
import UIKit

/// Share Extension entry point.
/// Receives shared files (PDF/EPUB) and passes them to the main app via URL scheme.
///
/// Note: This file is a placeholder for the Share Extension target.
/// Full implementation requires a separate Xcode target with its own bundle ID
/// and App Group entitlement (group.ai.papertok.paperreader).
class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        let providers = extensionItems.compactMap { $0.attachments }.flatMap { $0 }

        Task {
            let urls = await ShareHandler.extractFiles(from: providers)
            if !urls.isEmpty {
                let fileNames = urls.map { $0.lastPathComponent }.joined(separator: ",")
                let encoded = fileNames.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let openURL = URL(string: "paperreader://import?files=\(encoded)") {
                    // Open the main app to handle the import
                    await self.extensionContext?.open(openURL)
                }
            }
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
#endif
