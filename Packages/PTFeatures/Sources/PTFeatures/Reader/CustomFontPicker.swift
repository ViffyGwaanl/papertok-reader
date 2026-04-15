import SwiftUI
import Observation
import UniformTypeIdentifiers
import PTCore
import PTReader
import PTUI

/// Abstraction over `CustomFontRegistry` so view models can be tested without
/// touching the real CoreText registration path.
public protocol CustomFontRegistering: Sendable {
    func list() async -> [CustomFontDescriptor]
    func install(from sourceURL: URL) async throws -> CustomFontDescriptor
    func remove(_ id: String) async throws
}

extension CustomFontRegistry: CustomFontRegistering {}

@MainActor
@Observable
public final class CustomFontPickerViewModel {
    public private(set) var fonts: [CustomFontDescriptor] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    private let registry: any CustomFontRegistering

    public init(registry: any CustomFontRegistering) {
        self.registry = registry
    }

    public func refresh() async {
        fonts = await registry.list()
    }

    public func install(from url: URL) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            _ = try await registry.install(from: url)
            fonts = await registry.list()
        } catch let error as CustomFontRegistryError {
            errorMessage = Self.localizedMessage(for: error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func remove(_ descriptor: CustomFontDescriptor) async {
        errorMessage = nil
        do {
            try await registry.remove(descriptor.id)
            fonts = await registry.list()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public static func localizedMessage(for error: CustomFontRegistryError) -> String {
        switch error {
        case .unsupportedFormat:
            return AppLocalization.string("reader.fonts.custom.error.unsupported_format")
        case .copyFailed:
            return AppLocalization.string("reader.fonts.custom.error.copy_failed")
        case .registrationFailed:
            return AppLocalization.string("reader.fonts.custom.error.registration_failed")
        case .fontMetadataUnavailable:
            return AppLocalization.string("reader.fonts.custom.error.metadata_unavailable")
        case .notFound:
            return AppLocalization.string("reader.fonts.custom.error.metadata_unavailable")
        }
    }
}

public struct CustomFontPicker: View {
    @Bindable public var viewModel: CustomFontPickerViewModel
    @State private var isImporterPresented: Bool = false

    public init(viewModel: CustomFontPickerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        List {
            if let message = viewModel.errorMessage {
                Section {
                    Text(message)
                        .font(AppTypography.footnote)
                        .foregroundStyle(.red)
                }
            }

            if viewModel.fonts.isEmpty {
                Section {
                    VStack(spacing: AppSpacing.sm) {
                        Image(systemName: "textformat")
                            .font(.system(size: 36))
                            .foregroundStyle(Morandi.secondaryText)
                        Text("reader.fonts.custom.empty_title")
                            .font(AppTypography.headline)
                            .foregroundStyle(Morandi.primaryText)
                        Text("reader.fonts.custom.empty_subtitle")
                            .font(AppTypography.footnote)
                            .foregroundStyle(Morandi.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                }
            } else {
                Section {
                    ForEach(viewModel.fonts, id: \.id) { font in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(font.displayName)
                                .font(AppTypography.body)
                                .foregroundStyle(Morandi.primaryText)
                            Text(font.postscriptName)
                                .font(AppTypography.caption)
                                .foregroundStyle(Morandi.secondaryText)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await viewModel.remove(font) }
                            } label: {
                                Text("reader.fonts.custom.delete_action")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "reader.fonts.custom.section_title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isImporterPresented = true
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("reader.fonts.custom.add_button")
                    }
                }
                .disabled(viewModel.isLoading)
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.font],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await viewModel.install(from: url) }
            case .failure:
                break
            }
        }
        .task {
            await viewModel.refresh()
        }
    }
}
