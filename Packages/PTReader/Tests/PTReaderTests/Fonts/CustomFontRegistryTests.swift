import Foundation
import Testing
@testable import PTReader

// Test fixture font: iAWriterDuospace-Regular.ttf
// Copyright © iA Inc., released under the SIL Open Font License 1.1.
// Source: https://github.com/iaolo/iA-Fonts (via Readium swift-toolkit).
// Full license text: Packages/PTReader/Tests/PTReaderTests/Fonts/Resources/LICENSE-iAWriterDuospace.md

@Suite("CustomFontRegistry")
struct CustomFontRegistryTests {
    @Test("install copies the font file and registers it with CoreText")
    func installCopiesAndRegistersFont() async throws {
        let dir = Self.makeTempDir()
        defer { Self.cleanup(dir) }
        let registry = CustomFontRegistry(directory: dir)
        let source = try Self.stagedFontCopy(for: "install-copies")

        let descriptor = try await registry.install(from: source)

        #expect(!descriptor.id.isEmpty)
        #expect(!descriptor.postscriptName.isEmpty)
        #expect(!descriptor.displayName.isEmpty)

        let list = await registry.list()
        #expect(list.count == 1)
        #expect(list.first?.id == descriptor.id)

        let storedURL = dir.appendingPathComponent(descriptor.storedFilename())
        #expect(FileManager.default.fileExists(atPath: storedURL.path))
    }

    @Test("install rejects non-font files with unsupportedFormat")
    func installRejectsNonFontFile() async throws {
        let dir = Self.makeTempDir()
        defer { Self.cleanup(dir) }
        let registry = CustomFontRegistry(directory: dir)

        let bogus = dir.appendingPathComponent("not-a-font.txt")
        try "hello".write(to: bogus, atomically: true, encoding: .utf8)

        await #expect(throws: CustomFontRegistryError.unsupportedFormat("txt")) {
            _ = try await registry.install(from: bogus)
        }
    }

    @Test("remove unregisters and deletes the font file")
    func removeUnregistersAndDeletes() async throws {
        let dir = Self.makeTempDir()
        defer { Self.cleanup(dir) }
        let registry = CustomFontRegistry(directory: dir)
        let source = try Self.stagedFontCopy(for: "remove-case")
        let descriptor = try await registry.install(from: source)

        try await registry.remove(descriptor.id)

        let list = await registry.list()
        #expect(list.isEmpty)
        let storedURL = dir.appendingPathComponent(descriptor.storedFilename())
        #expect(!FileManager.default.fileExists(atPath: storedURL.path))
    }

    @Test("registerAll restores previously installed fonts from the manifest")
    func registerAllRestoresPreviouslyInstalledFonts() async throws {
        let dir = Self.makeTempDir()
        defer { Self.cleanup(dir) }

        let first = CustomFontRegistry(directory: dir)
        let source = try Self.stagedFontCopy(for: "register-all-case")
        let descriptor = try await first.install(from: source)

        let second = CustomFontRegistry(directory: dir)
        await second.registerAll()
        let list = await second.list()
        #expect(list.count == 1)
        #expect(list.first?.id == descriptor.id)
        #expect(list.first?.postscriptName == descriptor.postscriptName)
    }

    @Test("installing the same font twice yields a stable identifier")
    func idStableAcrossInstalls() async throws {
        let dir = Self.makeTempDir()
        defer { Self.cleanup(dir) }
        let registry = CustomFontRegistry(directory: dir)
        let firstSource = try Self.stagedFontCopy(for: "stable-id-1", preserveFilename: true)
        let secondSource = try Self.stagedFontCopy(for: "stable-id-2", preserveFilename: true)

        let a = try await registry.install(from: firstSource)
        let b = try await registry.install(from: secondSource)

        #expect(a.id == b.id)
        let list = await registry.list()
        #expect(list.count == 1)
    }

    // MARK: - Helpers

    private static func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperTokTests/Fonts/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Copies the bundled test font to a throwaway staging directory so that
    /// `install(from:)` can consume it without mutating the bundle resource.
    /// When `preserveFilename` is true the copy keeps the original filename so
    /// tests that care about stable-id behavior share the same source filename.
    private static func stagedFontCopy(for slug: String, preserveFilename: Bool = false) throws -> URL {
        let bundle = Bundle.module
        guard let original = bundle.url(forResource: "iAWriterDuospace-Regular", withExtension: "ttf") else {
            throw CustomFontRegistryError.fontMetadataUnavailable
        }
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperTokTests/FontStaging/\(slug)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let destination: URL
        if preserveFilename {
            destination = stagingDir.appendingPathComponent(original.lastPathComponent)
        } else {
            destination = stagingDir.appendingPathComponent("\(slug)-\(original.lastPathComponent)")
        }
        try FileManager.default.copyItem(at: original, to: destination)
        return destination
    }
}
