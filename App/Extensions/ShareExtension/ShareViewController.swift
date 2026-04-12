#if os(iOS)
import UIKit

/// Share Extension entry point.
/// Receives shared files (PDF/EPUB) and passes them to the main app via URL scheme.
class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        let providers = extensionItems.compactMap { $0.attachments }.flatMap { $0 }

        Task {
            let eventID = UUID().uuidString
            let requestedRoute = ShareDefaultRoute.current()
            if let event = await ShareHandler.captureEvent(
                from: providers,
                eventID: eventID,
                requestedRoute: requestedRoute
            ) {
                let encodedEventID = eventID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? eventID
                let openURL: URL?
                switch event.route {
                case .bookshelfImport:
                    openURL = URL(string: "paperreader://import?token=\(encodedEventID)")
                case .aiChat:
                    openURL = URL(string: "paperreader://ai?share_token=\(encodedEventID)")
                case .ask:
                    openURL = URL(string: "paperreader://shortcuts/ask?share_token=\(encodedEventID)")
                }

                if let openURL {
                    // Open the main app to handle the import
                    await self.extensionContext?.open(openURL)
                }
            }
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
#endif
