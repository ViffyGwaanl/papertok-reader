import Foundation
import PTCore

enum FlutterMigrationPlanner {
    static func legacyRoot(from flutterDBPath: URL) -> URL {
        let parent = flutterDBPath.deletingLastPathComponent()
        if parent.lastPathComponent == "databases" {
            return parent.deletingLastPathComponent()
        }
        return parent
    }

    static func destinationRoot(fileManager: FileManager = .default) -> URL {
        AppConfig.appGroupContainerURL(fileManager: fileManager)
    }

    static func remapBook(
        _ book: Book,
        legacyRoot: URL,
        destinationRoot: URL,
        fileManager: FileManager = .default
    ) throws -> Book {
        var migrated = book
        if let migratedFile = try migrateStoredPath(
            book.filePath,
            legacyRoot: legacyRoot,
            destinationRoot: destinationRoot,
            fileManager: fileManager
        ) {
            migrated.filePath = migratedFile.path
        }
        if let migratedCover = try migrateStoredPath(
            book.coverPath,
            legacyRoot: legacyRoot,
            destinationRoot: destinationRoot,
            fileManager: fileManager
        ) {
            migrated.coverPath = migratedCover.path
        }
        return migrated
    }

    @discardableResult
    static func copyMemoryIfPresent(
        legacyRoot: URL,
        destinationRoot: URL,
        fileManager: FileManager = .default
    ) throws -> Bool {
        try copyRelativeDirectory(
            named: "memory",
            legacyRoot: legacyRoot,
            destinationRoot: destinationRoot,
            fileManager: fileManager
        )
    }

    @discardableResult
    static func importLegacySettingsIfNeeded(
        from sourceDefaults: UserDefaults = .standard,
        to destinationDefaults: UserDefaults = AppConfig.groupDefaults
    ) -> Int {
        let keys = [
            AppConfig.Keys.themeMode,
            AppConfig.Keys.accentColorIndex,
            AppConfig.Keys.oledDarkMode,
            AppConfig.Keys.defaultFontSize,
            AppConfig.Keys.pageTurnMode,
            AppConfig.Keys.aiProviderID,
            AppConfig.Keys.aiModelID,
            AppConfig.Keys.aiSystemPrompt,
            AppConfig.Keys.aiThinkingLevel,
        ]

        var importedCount = 0
        for key in keys {
            guard destinationDefaults.object(forKey: key) == nil,
                  let value = sourceDefaults.object(forKey: key) else {
                continue
            }
            destinationDefaults.set(value, forKey: key)
            importedCount += 1
        }
        return importedCount
    }

    private static func migrateStoredPath(
        _ storedPath: String,
        legacyRoot: URL,
        destinationRoot: URL,
        fileManager: FileManager
    ) throws -> URL? {
        let trimmed = storedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let sourceURL = resolveSourceURL(storedPath: trimmed, legacyRoot: legacyRoot)
        guard fileManager.fileExists(atPath: sourceURL.path) else { return nil }

        let relativePath = relativePathForStorage(storedPath: trimmed, sourceURL: sourceURL, legacyRoot: legacyRoot)
        let destinationURL = destinationRoot.appendingPathComponent(relativePath, isDirectory: false)
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: destinationURL.path) == false {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
        return destinationURL
    }

    @discardableResult
    private static func copyRelativeDirectory(
        named directoryName: String,
        legacyRoot: URL,
        destinationRoot: URL,
        fileManager: FileManager
    ) throws -> Bool {
        let sourceDirectory = legacyRoot.appendingPathComponent(directoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: sourceDirectory.path) else { return false }

        let destinationDirectory: URL
        if directoryName == "memory" {
            destinationDirectory = try AppAIToolContextFactory.prepareMemoryDirectory(
                containerURL: destinationRoot,
                fileManager: fileManager
            )
        } else {
            destinationDirectory = destinationRoot.appendingPathComponent(directoryName, isDirectory: true)
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        }
        try copyDirectoryContents(from: sourceDirectory, to: destinationDirectory, fileManager: fileManager)
        return true
    }

    private static func resolveSourceURL(storedPath: String, legacyRoot: URL) -> URL {
        if storedPath.hasPrefix("/") {
            return URL(fileURLWithPath: storedPath)
        }
        let normalized = storedPath.replacingOccurrences(of: "\\", with: "/")
        return legacyRoot.appendingPathComponent(normalized)
    }

    private static func relativePathForStorage(storedPath: String, sourceURL: URL, legacyRoot: URL) -> String {
        let normalizedStoredPath = storedPath.replacingOccurrences(of: "\\", with: "/")
        if normalizedStoredPath.hasPrefix("/") {
            let legacyPrefix = legacyRoot.path.hasSuffix("/") ? legacyRoot.path : legacyRoot.path + "/"
            if sourceURL.path.hasPrefix(legacyPrefix) {
                return String(sourceURL.path.dropFirst(legacyPrefix.count))
            }
            return sourceURL.lastPathComponent
        }
        return normalizedStoredPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func copyDirectoryContents(from source: URL, to destination: URL, fileManager: FileManager) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for entry in contents {
            let target = destination.appendingPathComponent(entry.lastPathComponent, isDirectory: false)
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                try copyDirectoryContents(from: entry, to: target, fileManager: fileManager)
            } else if fileManager.fileExists(atPath: target.path) == false {
                try fileManager.copyItem(at: entry, to: target)
            }
        }
    }
}
