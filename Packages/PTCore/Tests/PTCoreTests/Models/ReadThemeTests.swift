import Testing
import Foundation
@testable import PTCore

@Suite("ReadTheme")
struct ReadThemeTests {
    @Test("Default theme has warm paper colors")
    func defaultTheme() {
        let theme = ReadTheme.defaultLight
        #expect(theme.backgroundColor == "FFFBFBF3")
        #expect(theme.textColor == "FF343434")
        #expect(theme.backgroundImagePath == "")
    }

    @Test("Roundtrips through database")
    func databaseRoundtrip() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = ReadThemeDAO(database: db)

        let theme = ReadTheme(
            id: nil,
            backgroundColor: "FF1A1A2E",
            textColor: "FFE0E0E0",
            backgroundImagePath: ""
        )

        let saved = try await dao.save(theme)
        #expect(saved.id != nil)

        let fetched = try await dao.fetchById(saved.id!)
        #expect(fetched != nil)
        #expect(fetched!.backgroundColor == "FF1A1A2E")
        #expect(fetched!.textColor == "FFE0E0E0")
    }

    @Test("FetchAll returns all themes")
    func fetchAll() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = ReadThemeDAO(database: db)

        _ = try await dao.save(ReadTheme(id: nil, backgroundColor: "FFF", textColor: "F00", backgroundImagePath: ""))
        _ = try await dao.save(ReadTheme(id: nil, backgroundColor: "000", textColor: "FFF", backgroundImagePath: ""))

        let all = try await dao.fetchAll()
        #expect(all.count == 2)
    }
}
