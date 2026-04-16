import Foundation
import SwiftUI

@MainActor
@Observable
public final class ReaderAIPanelState {
    public var isOpen: Bool
    public var dockSide: DockSide
    public var panelWidth: CGFloat

    public enum DockSide: String, Codable, CaseIterable, Sendable {
        case leading, trailing
    }

    public init(isOpen: Bool = false, dockSide: DockSide = .trailing, panelWidth: CGFloat = 380) {
        self.isOpen = isOpen
        self.dockSide = dockSide
        self.panelWidth = panelWidth
    }

    public func toggle() { isOpen.toggle() }

    public var clampedWidth: CGFloat {
        max(320, min(panelWidth, 600))
    }

    public func resolvedPresentationMode(containerWidth: CGFloat) -> PresentationMode {
        containerWidth < 600 ? .sheet : .sidePanel
    }

    public enum PresentationMode: Sendable, Equatable {
        case sheet, sidePanel
    }
}
