import Foundation
import Testing
@testable import PTFeatures
import PTReader

@Suite("CustomFontPickerViewModel")
@MainActor
struct CustomFontPickerViewModelTests {
    @Test("refresh loads fonts from the registry")
    func refreshLoadsFromRegistry() async {
        let stub = StubRegistry(
            initial: [CustomFontPickerViewModelTests.makeDescriptor(id: "a", name: "A")]
        )
        let viewModel = CustomFontPickerViewModel(registry: stub)

        await viewModel.refresh()

        #expect(viewModel.fonts.count == 1)
        #expect(viewModel.fonts.first?.displayName == "A")
        #expect(viewModel.errorMessage == nil)
    }

    @Test("successful install refreshes the list")
    func successfulInstallRefreshesList() async {
        let stub = StubRegistry(initial: [])
        let newDescriptor = CustomFontPickerViewModelTests.makeDescriptor(id: "new", name: "Brand New")
        stub.installResult = .success(newDescriptor)
        stub.postInstallList = [newDescriptor]
        let viewModel = CustomFontPickerViewModel(registry: stub)

        await viewModel.install(from: URL(fileURLWithPath: "/tmp/new.ttf"))

        #expect(viewModel.fonts.count == 1)
        #expect(viewModel.fonts.first?.id == "new")
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test("install failure surfaces a localized error and leaves the list untouched")
    func installFailureSurfacesError() async {
        let existing = CustomFontPickerViewModelTests.makeDescriptor(id: "old", name: "Old")
        let stub = StubRegistry(initial: [existing])
        stub.installResult = .failure(.unsupportedFormat("txt"))
        let viewModel = CustomFontPickerViewModel(registry: stub)
        await viewModel.refresh()

        await viewModel.install(from: URL(fileURLWithPath: "/tmp/bogus.txt"))

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.fonts.count == 1)
        #expect(viewModel.isLoading == false)
    }

    @Test("remove drops the font and refreshes the list")
    func removeDropsFont() async {
        let descriptor = CustomFontPickerViewModelTests.makeDescriptor(id: "remove-me", name: "Removable")
        let stub = StubRegistry(initial: [descriptor])
        let viewModel = CustomFontPickerViewModel(registry: stub)
        await viewModel.refresh()

        await viewModel.remove(descriptor)

        #expect(viewModel.fonts.isEmpty)
        #expect(stub.removedIDs == ["remove-me"])
    }

    // MARK: - Helpers

    private static func makeDescriptor(id: String, name: String) -> CustomFontDescriptor {
        CustomFontDescriptor(
            id: id,
            originalFilename: "\(name).ttf",
            postscriptName: name,
            displayName: name,
            installedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

private final class StubRegistry: CustomFontRegistering, @unchecked Sendable {
    var current: [CustomFontDescriptor]
    var postInstallList: [CustomFontDescriptor] = []
    var installResult: Result<CustomFontDescriptor, CustomFontRegistryError>?
    var removedIDs: [String] = []

    init(initial: [CustomFontDescriptor]) {
        self.current = initial
    }

    func list() async -> [CustomFontDescriptor] { current }

    func install(from sourceURL: URL) async throws -> CustomFontDescriptor {
        guard let result = installResult else {
            throw CustomFontRegistryError.fontMetadataUnavailable
        }
        switch result {
        case .success(let descriptor):
            current = postInstallList
            return descriptor
        case .failure(let error):
            throw error
        }
    }

    func remove(_ id: String) async throws {
        removedIDs.append(id)
        current.removeAll { $0.id == id }
    }
}
