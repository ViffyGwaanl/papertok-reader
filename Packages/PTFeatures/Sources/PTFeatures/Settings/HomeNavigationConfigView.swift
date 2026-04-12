import SwiftUI
import PTUI

/// Settings screen for customizing the home navigation tabs: toggling
/// individual tabs on/off and reordering via drag. Settings is always pinned
/// on and cannot be disabled or removed.
public struct HomeNavigationConfigView: View {
    @State private var order: [AppTab]
    @State private var enabled: Set<AppTab>

    public init() {
        let defaults = UserDefaults(suiteName: "group.ai.papertok.paperreader") ?? .standard
        let storedOrder: [AppTab]
        if let raw = defaults.stringArray(forKey: "home_nav_tab_order") {
            storedOrder = raw.compactMap { AppTab(rawValue: $0) }
        } else {
            storedOrder = AppTab.defaultOrder
        }
        let storedEnabled: Set<AppTab>
        if let raw = defaults.stringArray(forKey: "home_nav_enabled_tabs") {
            var set = Set(raw.compactMap { AppTab(rawValue: $0) })
            set.insert(.settings)
            storedEnabled = set
        } else {
            storedEnabled = Set(AppTab.allCases)
        }
        _order = State(initialValue: storedOrder)
        _enabled = State(initialValue: storedEnabled)
    }

    public var body: some View {
        List {
            previewSection
            tabsSection
            resetSection
        }
        .navigationTitle(String(localized: "settings.home_navigation"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        #endif
    }

    private var previewSection: some View {
        Section("Preview") {
            HStack(spacing: AppSpacing.md) {
                ForEach(order.filter { enabled.contains($0) }) { tab in
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(Morandi.accent)
                        Text(tab.title)
                            .font(AppTypography.caption2)
                            .foregroundStyle(Morandi.primaryText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, AppSpacing.sm)
        }
    }

    private var tabsSection: some View {
        Section("Tabs") {
            ForEach(order) { tab in
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: tab.icon)
                        .foregroundStyle(Morandi.accent)
                        .frame(width: 28)
                    Text(tab.title)
                        .foregroundStyle(Morandi.primaryText)
                    Spacer()
                    if tab == .settings {
                        Text("Pinned")
                            .font(AppTypography.caption2)
                            .foregroundStyle(Morandi.tertiaryText)
                    } else {
                        Toggle("", isOn: Binding(
                            get: { enabled.contains(tab) },
                            set: { newValue in
                                if newValue { enabled.insert(tab) } else { enabled.remove(tab) }
                                persist()
                            }
                        ))
                        .labelsHidden()
                        .tint(Morandi.accent)
                    }
                }
            }
            .onMove(perform: move)
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset to Defaults") {
                AppTab.resetConfiguration()
                order = AppTab.defaultOrder
                enabled = Set(AppTab.allCases)
            }
            .foregroundStyle(Morandi.accent)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        AppTab.saveConfiguration(order: order, enabled: enabled)
    }
}
