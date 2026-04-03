# Phase 4: PTUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the PTUI Swift package — Morandi color palette, typography system, reusable SwiftUI components (buttons, cards, chips, dialogs), and custom ViewModifiers for consistent Apple-style UI.

**Architecture:** PTUI depends only on PTCore. It provides the design system tokens (colors, typography, spacing) and reusable SwiftUI components. All UI in PTFeatures and the App target will import PTUI for consistent styling. The Morandi palette uses low-saturation earth tones as the primary design language.

**Tech Stack:** Swift 5.9+, SwiftUI, PTCore, Swift Testing

---

## File Structure

```
Packages/PTUI/
├── Package.swift
├── Sources/PTUI/
│   ├── PTUI.swift                      # Module entry
│   ├── Theme/
│   │   ├── MorandiPalette.swift        # Color definitions (30+ Morandi colors)
│   │   ├── AppTypography.swift         # Font styles and sizes
│   │   └── AppSpacing.swift            # Spacing constants
│   ├── Components/
│   │   ├── PTButton.swift              # Styled button variants
│   │   ├── PTCard.swift                # Card container with shadow
│   │   ├── PTChip.swift                # Filter/tag chips
│   │   └── PTSearchBar.swift           # Search input
│   └── Modifiers/
│       └── PTModifiers.swift           # Custom ViewModifiers
└── Tests/PTUITests/
    ├── Theme/
    │   └── MorandiPaletteTests.swift
    └── PTUIImportTests.swift
```

---

### Task 1: Package.swift and Module Entry

**Files:**
- Create: `Packages/PTUI/Package.swift`
- Create: `Packages/PTUI/Sources/PTUI/PTUI.swift`
- Create: `Packages/PTUI/Tests/PTUITests/PTUIImportTests.swift`

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PTUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PTUI", targets: ["PTUI"]),
    ],
    dependencies: [
        .package(path: "../PTCore"),
    ],
    targets: [
        .target(
            name: "PTUI",
            dependencies: ["PTCore"]
        ),
        .testTarget(
            name: "PTUITests",
            dependencies: ["PTUI"]
        ),
    ]
)
```

- [ ] **Step 2: Create module entry**

```swift
// PTUI — Design system, Morandi palette, reusable SwiftUI components
import Foundation
import SwiftUI
@_exported import PTCore
```

- [ ] **Step 3: Create placeholder test**

```swift
import Testing
@testable import PTUI

@Suite("PTUI Module")
struct PTUIImportTests {
    @Test("Module imports successfully")
    func moduleImports() {
        #expect(true)
    }
}
```

- [ ] **Step 4: Verify and commit**

Run: `cd Packages/PTUI && swift test`

```bash
git add Packages/PTUI/
git commit -m "feat(PTUI): initialize package with PTCore dependency"
```

---

### Task 2: Morandi Color Palette

**Files:**
- Create: `Packages/PTUI/Sources/PTUI/Theme/MorandiPalette.swift`
- Test: `Packages/PTUI/Tests/PTUITests/Theme/MorandiPaletteTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import Testing
import SwiftUI
@testable import PTUI

@Suite("MorandiPalette")
struct MorandiPaletteTests {
    @Test("Primary colors are defined")
    func primaryColors() {
        #expect(Morandi.sage != Color.clear)
        #expect(Morandi.dustyRose != Color.clear)
        #expect(Morandi.warmGray != Color.clear)
        #expect(Morandi.stone != Color.clear)
        #expect(Morandi.clay != Color.clear)
    }

    @Test("Semantic colors are defined")
    func semanticColors() {
        #expect(Morandi.primaryText != Color.clear)
        #expect(Morandi.secondaryText != Color.clear)
        #expect(Morandi.background != Color.clear)
        #expect(Morandi.cardBackground != Color.clear)
        #expect(Morandi.accent != Color.clear)
    }

    @Test("Accent presets has at least 6 options")
    func accentPresets() {
        #expect(Morandi.accentPresets.count >= 6)
    }

    @Test("Highlight colors map to 5 annotation colors")
    func highlightColors() {
        #expect(Morandi.highlightYellow != Color.clear)
        #expect(Morandi.highlightRed != Color.clear)
        #expect(Morandi.highlightBlue != Color.clear)
        #expect(Morandi.highlightGreen != Color.clear)
        #expect(Morandi.highlightPurple != Color.clear)
    }
}
```

- [ ] **Step 2: Implement MorandiPalette**

```swift
import SwiftUI

/// Morandi color palette — low-saturation earth tones for a premium reading experience.
public enum Morandi {
    // MARK: - Core Palette (低饱和度莫兰迪色系)

    /// Sage green — primary brand color
    public static let sage = Color(hex: "8FA68A")
    /// Dusty rose — warm accent
    public static let dustyRose = Color(hex: "C4A4A0")
    /// Warm gray — neutral base
    public static let warmGray = Color(hex: "A8A098")
    /// Stone — cool neutral
    public static let stone = Color(hex: "B8B0A8")
    /// Clay — earthy warmth
    public static let clay = Color(hex: "C0A890")
    /// Lavender mist
    public static let lavender = Color(hex: "B8A8C8")
    /// Powder blue
    public static let powder = Color(hex: "A0B8C8")
    /// Sand
    public static let sand = Color(hex: "D0C4B0")
    /// Mauve
    public static let mauve = Color(hex: "C8A0B0")
    /// Moss
    public static let moss = Color(hex: "98A890")
    /// Taupe
    public static let taupe = Color(hex: "B0A498")
    /// Mist
    public static let mist = Color(hex: "C8D0D0")

    // MARK: - Semantic Colors

    /// Primary text color (adapts to light/dark)
    public static let primaryText = Color(hex: "343434")
    /// Secondary text color
    public static let secondaryText = Color(hex: "8A8A8E")
    /// Tertiary text color
    public static let tertiaryText = Color(hex: "B0B0B4")
    /// Main background
    public static let background = Color(hex: "FAF8F5")
    /// Card/surface background
    public static let cardBackground = Color(hex: "FFFFFF")
    /// Default accent (sage)
    public static let accent = sage
    /// Divider/separator
    public static let divider = Color(hex: "E8E4E0")
    /// Destructive action
    public static let destructive = Color(hex: "C87070")

    // MARK: - Dark Mode Variants

    public static let darkBackground = Color(hex: "1A1A2E")
    public static let darkCardBackground = Color(hex: "262640")
    public static let darkPrimaryText = Color(hex: "E8E4E0")
    public static let darkSecondaryText = Color(hex: "9090A0")

    // MARK: - Highlight Colors (for annotations, Morandi-tinted)

    public static let highlightYellow = Color(hex: "E8D890")
    public static let highlightRed = Color(hex: "D09898")
    public static let highlightBlue = Color(hex: "90B0D0")
    public static let highlightGreen = Color(hex: "98C8A0")
    public static let highlightPurple = Color(hex: "B898C8")

    // MARK: - Accent Presets (for user customization)

    public static let accentPresets: [(name: String, color: Color)] = [
        ("Sage", sage),
        ("Dusty Rose", dustyRose),
        ("Lavender", lavender),
        ("Powder Blue", powder),
        ("Clay", clay),
        ("Mauve", mauve),
        ("Moss", moss),
        ("Stone", stone),
    ]
}

// MARK: - Color Hex Extension

extension Color {
    /// Initialize from a hex string (6 or 8 characters, with or without #).
    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b, a: Double
        switch hex.count {
        case 6:
            (r, g, b, a) = (
                Double((int >> 16) & 0xFF) / 255,
                Double((int >> 8) & 0xFF) / 255,
                Double(int & 0xFF) / 255,
                1.0
            )
        case 8:
            (a, r, g, b) = (
                Double((int >> 24) & 0xFF) / 255,
                Double((int >> 16) & 0xFF) / 255,
                Double((int >> 8) & 0xFF) / 255,
                Double(int & 0xFF) / 255
            )
        default:
            (r, g, b, a) = (0, 0, 0, 1)
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
```

- [ ] **Step 3: Run tests and commit**

Run: `cd Packages/PTUI && swift test --filter MorandiPaletteTests`

```bash
git add Packages/PTUI/Sources/PTUI/Theme/MorandiPalette.swift Packages/PTUI/Tests/PTUITests/Theme/MorandiPaletteTests.swift
git commit -m "feat(PTUI): add Morandi color palette with semantic colors and hex extension"
```

---

### Task 3: Typography and Spacing

**Files:**
- Create: `Packages/PTUI/Sources/PTUI/Theme/AppTypography.swift`
- Create: `Packages/PTUI/Sources/PTUI/Theme/AppSpacing.swift`

- [ ] **Step 1: Create AppTypography**

```swift
import SwiftUI

/// Typography scale following Apple HIG with Morandi design sensibility.
public enum AppTypography {
    public static let largeTitle = Font.largeTitle
    public static let title = Font.title
    public static let title2 = Font.title2
    public static let title3 = Font.title3
    public static let headline = Font.headline
    public static let body = Font.body
    public static let callout = Font.callout
    public static let subheadline = Font.subheadline
    public static let footnote = Font.footnote
    public static let caption = Font.caption
    public static let caption2 = Font.caption2

    /// Monospaced for code/technical display.
    public static let mono = Font.system(.body, design: .monospaced)
    /// Serif for reading/literary context.
    public static let serif = Font.system(.body, design: .serif)
}
```

- [ ] **Step 2: Create AppSpacing**

```swift
import SwiftUI

/// Spacing scale (4pt grid) for consistent layout.
public enum AppSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48

    /// Standard card corner radius.
    public static let cornerRadius: CGFloat = 12
    /// Small corner radius (chips, tags).
    public static let cornerRadiusSmall: CGFloat = 8
    /// Standard card shadow radius.
    public static let shadowRadius: CGFloat = 4
}
```

- [ ] **Step 3: Build and commit**

Run: `cd Packages/PTUI && swift build`

```bash
git add Packages/PTUI/Sources/PTUI/Theme/AppTypography.swift Packages/PTUI/Sources/PTUI/Theme/AppSpacing.swift
git commit -m "feat(PTUI): add AppTypography and AppSpacing design tokens"
```

---

### Task 4: SwiftUI Components (PTButton, PTCard, PTChip, PTSearchBar)

**Files:**
- Create: `Packages/PTUI/Sources/PTUI/Components/PTButton.swift`
- Create: `Packages/PTUI/Sources/PTUI/Components/PTCard.swift`
- Create: `Packages/PTUI/Sources/PTUI/Components/PTChip.swift`
- Create: `Packages/PTUI/Sources/PTUI/Components/PTSearchBar.swift`

- [ ] **Step 1: Create PTButton**

```swift
import SwiftUI

/// Morandi-styled button with primary/secondary/destructive variants.
public struct PTButton: View {
    public enum Style { case primary, secondary, destructive, ghost }

    let title: String
    let style: Style
    let action: () -> Void

    public init(_ title: String, style: Style = .primary, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.headline)
                .frame(maxWidth: style == .ghost ? nil : .infinity)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundColor)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall))
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return Morandi.accent
        case .destructive: return .white
        case .ghost: return Morandi.accent
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return Morandi.accent
        case .secondary: return Morandi.accent.opacity(0.12)
        case .destructive: return Morandi.destructive
        case .ghost: return .clear
        }
    }
}
```

- [ ] **Step 2: Create PTCard**

```swift
import SwiftUI

/// Card container with Morandi shadow and corner radius.
public struct PTCard<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(AppSpacing.lg)
            .background(Morandi.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
            .shadow(color: Morandi.warmGray.opacity(0.15), radius: AppSpacing.shadowRadius, y: 2)
    }
}
```

- [ ] **Step 3: Create PTChip**

```swift
import SwiftUI

/// Filter/tag chip with selected state.
public struct PTChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    public init(_ title: String, isSelected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.subheadline)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .white : Morandi.secondaryText)
        .background(
            isSelected ? Morandi.accent : Morandi.divider.opacity(0.5),
            in: Capsule()
        )
    }
}
```

- [ ] **Step 4: Create PTSearchBar**

```swift
import SwiftUI

/// Search bar with Morandi styling.
public struct PTSearchBar: View {
    @Binding var text: String
    let placeholder: String

    public init(text: Binding<String>, placeholder: String = "Search") {
        self._text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Morandi.secondaryText)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Morandi.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(Morandi.divider.opacity(0.3), in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall))
    }
}
```

- [ ] **Step 5: Build and commit**

Run: `cd Packages/PTUI && swift build`

```bash
git add Packages/PTUI/Sources/PTUI/Components/
git commit -m "feat(PTUI): add PTButton, PTCard, PTChip, PTSearchBar components"
```

---

### Task 5: Custom ViewModifiers

**Files:**
- Create: `Packages/PTUI/Sources/PTUI/Modifiers/PTModifiers.swift`

- [ ] **Step 1: Create PTModifiers**

```swift
import SwiftUI

// MARK: - Card Modifier

public struct PTCardModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .padding(AppSpacing.lg)
            .background(Morandi.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
            .shadow(color: Morandi.warmGray.opacity(0.15), radius: AppSpacing.shadowRadius, y: 2)
    }
}

// MARK: - Section Header Modifier

public struct PTSectionHeaderModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .font(AppTypography.subheadline)
            .foregroundStyle(Morandi.secondaryText)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

// MARK: - View Extensions

extension View {
    /// Apply Morandi card styling (background, corner radius, shadow).
    public func ptCard() -> some View {
        modifier(PTCardModifier())
    }

    /// Apply section header styling.
    public func ptSectionHeader() -> some View {
        modifier(PTSectionHeaderModifier())
    }

    /// Apply Morandi divider below.
    public func ptDivider() -> some View {
        self.overlay(alignment: .bottom) {
            Morandi.divider.frame(height: 0.5)
        }
    }
}
```

- [ ] **Step 2: Build and commit**

Run: `cd Packages/PTUI && swift build`

```bash
git add Packages/PTUI/Sources/PTUI/Modifiers/PTModifiers.swift
git commit -m "feat(PTUI): add PTCardModifier, PTSectionHeaderModifier, and View extensions"
```

---

### Task 6: Run Full Test Suite and Push

- [ ] **Step 1: Run all package tests**

```bash
cd Packages/PTCore && swift test 2>&1 | tail -5
cd Packages/PTNetworking && swift test 2>&1 | tail -5
cd Packages/PTReader && swift test 2>&1 | tail -5
cd Packages/PTUI && swift test 2>&1 | tail -5
```

- [ ] **Step 2: Push**

```bash
git push origin swift-native
```

---

## Summary

| Task | Component | Tests |
|------|-----------|-------|
| 1 | Package setup | 1 import test |
| 2 | Morandi palette + Color.hex | 4 tests |
| 3 | Typography + Spacing | 0 (constants) |
| 4 | PTButton, PTCard, PTChip, PTSearchBar | 0 (SwiftUI views) |
| 5 | ViewModifiers | 0 (modifiers) |
| 6 | Full suite verification | Run all |

**Total: 6 tasks, ~5 new tests**
