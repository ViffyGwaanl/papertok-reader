#if canImport(UIKit)
import SwiftUI
import UIKit
import PTCore
import ReadiumNavigator
import ReadiumShared

/// SwiftUI wrapper for Readium EPUBNavigatorViewController.
///
/// Usage:
/// ```swift
/// EPUBReaderView(publication: pub, coordinator: coordinator)
/// ```
public struct EPUBReaderView: UIViewControllerRepresentable {
    public let publication: Publication
    public let initialLocator: Locator?
    public let readingPreferences: EPUBReadingPreferencesSnapshot
    /// Optional custom CSS (built via `EPUBCustomCSSBuilder`) to inject into
    /// the Readium navigator on every page change.
    public let customCSS: String?
    @Bindable public var coordinator: EPUBNavigatorCoordinator

    public init(
        publication: Publication,
        coordinator: EPUBNavigatorCoordinator,
        initialLocator: Locator? = nil,
        readingPreferences: EPUBReadingPreferencesSnapshot = .init(readingPreferences: ReadingPreferences()),
        customCSS: String? = nil
    ) {
        self.publication = publication
        self.coordinator = coordinator
        self.initialLocator = initialLocator
        self.readingPreferences = readingPreferences
        self.customCSS = customCSS
    }

    static func loadFailureMessage(for error: Error) -> String {
        AppLocalization.userFacingErrorMessage(
            for: error,
            fallbackKey: "errors.reader.cannot_open",
            fallback: "Cannot open this book."
        )
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        do {
            var config = EPUBNavigatorViewController.Configuration()
            config.preferences = readingPreferences.preferences
            let vc = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: initialLocator,
                config: config
            )
            vc.delegate = coordinator
            coordinator.setReadingPreferences(readingPreferences)
            coordinator.navigatorViewController = vc
            return vc
        } catch {
            // If navigator creation fails, return a placeholder
            let errorVC = UIViewController()
            let label = UILabel()
            label.text = Self.loadFailureMessage(for: error)
            label.textAlignment = .center
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            errorVC.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: errorVC.view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: errorVC.view.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: errorVC.view.leadingAnchor, constant: 20),
                label.trailingAnchor.constraint(lessThanOrEqualTo: errorVC.view.trailingAnchor, constant: -20),
            ])
            return errorVC
        }
    }

    public func updateUIViewController(_ vc: UIViewController, context: Context) {
        coordinator.setReadingPreferences(readingPreferences)
        if let css = customCSS, css.isEmpty == false {
            coordinator.applyCustomCSS(css)
        }
    }
}
#endif
