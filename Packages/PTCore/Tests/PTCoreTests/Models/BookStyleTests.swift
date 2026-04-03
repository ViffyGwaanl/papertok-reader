import Testing
import Foundation
@testable import PTCore

@Suite("BookStyle")
struct BookStyleTests {
    @Test("Default values are correct")
    func defaultValues() {
        let style = BookStyle.default
        #expect(style.fontSize == 1.4)
        #expect(style.fontFamily == "Arial")
        #expect(style.lineHeight == 1.8)
        #expect(style.letterSpacing == 0.0)
        #expect(style.wordSpacing == 0.0)
        #expect(style.paragraphSpacing == 1.0)
        #expect(style.sideMargin == 6.0)
        #expect(style.topMargin == 90.0)
        #expect(style.bottomMargin == 50.0)
    }

    @Test("Roundtrips through database")
    func databaseRoundtrip() async throws {
        let db = try AppDatabase.makeInMemory()
        let dao = BookStyleDAO(database: db)

        var style = BookStyle.default
        style.fontSize = 2.0
        style.fontFamily = "Georgia"
        style.lineHeight = 2.2

        let saved = try await dao.save(style)
        #expect(saved.id != nil)

        let fetched = try await dao.fetchById(saved.id!)
        #expect(fetched != nil)
        #expect(fetched!.fontSize == 2.0)
        #expect(fetched!.fontFamily == "Georgia")
        #expect(fetched!.lineHeight == 2.2)
    }

    @Test("JSON serialization roundtrips")
    func jsonRoundtrip() throws {
        var style = BookStyle.default
        style.fontSize = 1.8
        style.fontFamily = "Source Han Serif SC"

        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(BookStyle.self, from: data)
        #expect(decoded.fontSize == 1.8)
        #expect(decoded.fontFamily == "Source Han Serif SC")
    }
}
