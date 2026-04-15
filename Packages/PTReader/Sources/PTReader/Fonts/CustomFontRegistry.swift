import Foundation
import CoreText
import CoreGraphics
import CryptoKit

public struct CustomFontDescriptor: Hashable, Sendable, Codable {
    public let id: String
    public let originalFilename: String
    public let postscriptName: String
    public let displayName: String
    public let installedAt: Date

    public init(
        id: String,
        originalFilename: String,
        postscriptName: String,
        displayName: String,
        installedAt: Date
    ) {
        self.id = id
        self.originalFilename = originalFilename
        self.postscriptName = postscriptName
        self.displayName = displayName
        self.installedAt = installedAt
    }

    /// Filename inside the registry directory: "<id><ext>".
    public func storedFilename() -> String {
        let ext = (originalFilename as NSString).pathExtension
        if ext.isEmpty {
            return id
        }
        return "\(id).\(ext.lowercased())"
    }
}

public enum CustomFontRegistryError: Error, Equatable {
    case unsupportedFormat(String)
    case copyFailed(String)
    case registrationFailed(String)
    case fontMetadataUnavailable
    case notFound(id: String)
}

/// Manages the user's library of custom fonts.
///
/// Fonts are copied into a shared directory (typically the app-group container),
/// registered with CoreText in `.process` scope (portable across iOS and macOS),
/// and persisted via a `descriptors.json` manifest for fast listing.
/// Shared singleton for the default app-group-backed font directory. Consumers
/// that don't need a custom directory (unit tests) should call this accessor
/// instead of constructing their own instance so CoreText registration state
/// stays consistent across the process.
public enum CustomFontRegistryProvider {
    private static let _shared: CustomFontRegistry = {
        let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.ai.papertok.paperreader"
        ) ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("CustomFonts", isDirectory: true)
        return CustomFontRegistry(directory: directory)
    }()

    public static var shared: CustomFontRegistry { _shared }
}

public actor CustomFontRegistry {
    public static let supportedExtensions: Set<String> = ["ttf", "otf", "ttc"]
    private static let manifestFilename = "descriptors.json"

    private let directory: URL
    private let fileManager: FileManager
    private var descriptors: [CustomFontDescriptor] = []
    private var registeredURLs: Set<URL> = []
    private var didLoadManifest: Bool = false

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public func list() async -> [CustomFontDescriptor] {
        loadManifestIfNeeded()
        return descriptors
    }

    /// Registers every font currently tracked by the manifest with CoreText.
    /// Call once at app launch.
    public func registerAll() async {
        ensureDirectoryExists()
        loadManifestIfNeeded()
        for descriptor in descriptors {
            let url = directory.appendingPathComponent(descriptor.storedFilename())
            guard fileManager.fileExists(atPath: url.path) else { continue }
            _ = registerFont(at: url)
        }
    }

    @discardableResult
    public func install(from sourceURL: URL) async throws -> CustomFontDescriptor {
        ensureDirectoryExists()
        loadManifestIfNeeded()

        let ext = sourceURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw CustomFontRegistryError.unsupportedFormat(ext)
        }

        let originalFilename = sourceURL.lastPathComponent
        let id = Self.stableID(for: originalFilename)
        let destinationURL = directory.appendingPathComponent("\(id).\(ext)")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw CustomFontRegistryError.copyFailed(error.localizedDescription)
        }

        let metadata: (postScript: String, family: String)
        do {
            metadata = try Self.extractMetadata(from: destinationURL)
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            if let registryError = error as? CustomFontRegistryError {
                throw registryError
            }
            throw CustomFontRegistryError.fontMetadataUnavailable
        }

        guard registerFont(at: destinationURL) else {
            try? fileManager.removeItem(at: destinationURL)
            throw CustomFontRegistryError.registrationFailed(metadata.postScript)
        }

        let descriptor = CustomFontDescriptor(
            id: id,
            originalFilename: originalFilename,
            postscriptName: metadata.postScript,
            displayName: metadata.family.isEmpty ? metadata.postScript : metadata.family,
            installedAt: Date()
        )

        descriptors.removeAll { $0.id == id }
        descriptors.append(descriptor)
        persistManifest()
        return descriptor
    }

    public func remove(_ id: String) async throws {
        loadManifestIfNeeded()
        guard let index = descriptors.firstIndex(where: { $0.id == id }) else {
            throw CustomFontRegistryError.notFound(id: id)
        }
        let descriptor = descriptors[index]
        let url = directory.appendingPathComponent(descriptor.storedFilename())
        unregisterFont(at: url)
        try? fileManager.removeItem(at: url)
        descriptors.remove(at: index)
        persistManifest()
    }

    // MARK: - Private

    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func loadManifestIfNeeded() {
        guard !didLoadManifest else { return }
        didLoadManifest = true
        ensureDirectoryExists()
        let manifestURL = directory.appendingPathComponent(Self.manifestFilename)
        guard let data = try? Data(contentsOf: manifestURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([CustomFontDescriptor].self, from: data) {
            descriptors = decoded
        }
    }

    private func persistManifest() {
        ensureDirectoryExists()
        let manifestURL = directory.appendingPathComponent(Self.manifestFilename)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(descriptors) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    @discardableResult
    private func registerFont(at url: URL) -> Bool {
        if registeredURLs.contains(url) {
            return true
        }
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if ok {
            registeredURLs.insert(url)
        } else if let cfError = error?.takeRetainedValue() {
            // Font may already be registered in this process from a prior launch; treat
            // "already registered" as success so registerAll() is idempotent.
            let code = CFErrorGetCode(cfError)
            // Treat "already registered" and "duplicated name" as success so the registry
            // stays idempotent across re-launches and identical-content reinstalls.
            if code == CTFontManagerError.alreadyRegistered.rawValue
                || code == CTFontManagerError.duplicatedName.rawValue {
                registeredURLs.insert(url)
                return true
            }
        }
        return ok
    }

    private func unregisterFont(at url: URL) {
        guard registeredURLs.contains(url) else { return }
        var error: Unmanaged<CFError>?
        _ = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, &error)
        registeredURLs.remove(url)
    }

    private static func extractMetadata(from url: URL) throws -> (postScript: String, family: String) {
        guard let dataProvider = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(dataProvider) else {
            throw CustomFontRegistryError.fontMetadataUnavailable
        }
        let postScript = (cgFont.postScriptName as String?) ?? ""
        guard !postScript.isEmpty else {
            throw CustomFontRegistryError.fontMetadataUnavailable
        }
        let ctFont = CTFontCreateWithGraphicsFont(cgFont, 12.0, nil, nil)
        let family = (CTFontCopyFamilyName(ctFont) as String?) ?? postScript
        return (postScript, family)
    }

    private static func stableID(for originalFilename: String) -> String {
        let data = Data(originalFilename.utf8)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }
}
