#if canImport(UIKit)
import SwiftUI
import UIKit
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
    @Bindable public var coordinator: EPUBNavigatorCoordinator

    public init(
        publication: Publication,
        coordinator: EPUBNavigatorCoordinator,
        initialLocator: Locator? = nil
    ) {
        self.publication = publication
        self.coordinator = coordinator
        self.initialLocator = initialLocator
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        do {
            let config = EPUBNavigatorViewController.Configuration()
            let vc = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: initialLocator,
                config: config
            )
            vc.delegate = coordinator
            coordinator.navigatorViewController = vc
            return vc
        } catch {
            // If navigator creation fails, return a placeholder
            let errorVC = UIViewController()
            let label = UILabel()
            label.text = "Failed to load EPUB: \(error.localizedDescription)"
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
        // Locator navigation handled via coordinator.navigate(to:)
    }
}
#endif
