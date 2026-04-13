import SwiftUI

public enum AppSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
    public static let cornerRadius: CGFloat = 12
    public static let cornerRadiusSmall: CGFloat = 8
    public static let shadowRadius: CGFloat = 4
}

/// Material Design-inspired elevation tiers.
///
/// Tuple shape `(radius, x, y)` lets callers destructure into `shadow(…)` parameters.
/// Prefer the `ptShadow(level:)` view modifier for default usage — it pairs each level with
/// the adaptive `Morandi.shadow` color so shadows render correctly in both light and dark mode.
public enum AppElevation {
    public static let level1: (radius: CGFloat, x: CGFloat, y: CGFloat) = (4, 0, 2)
    public static let level2: (radius: CGFloat, x: CGFloat, y: CGFloat) = (8, 0, 4)
    public static let level3: (radius: CGFloat, x: CGFloat, y: CGFloat) = (16, 0, 8)
    public static let level4: (radius: CGFloat, x: CGFloat, y: CGFloat) = (24, 0, 12)
}

public extension View {
    /// Applies an adaptive elevation shadow using `Morandi.shadow`.
    /// - Parameter level: Elevation tier (1–4). Higher values imply more distance from the surface.
    func ptShadow(level: Int = 1) -> some View {
        let elev: (radius: CGFloat, x: CGFloat, y: CGFloat) = {
            switch level {
            case 2: return AppElevation.level2
            case 3: return AppElevation.level3
            case 4: return AppElevation.level4
            default: return AppElevation.level1
            }
        }()
        return self.shadow(color: Morandi.shadow, radius: elev.radius, x: elev.x, y: elev.y)
    }
}
