#if canImport(UIKit)
import Foundation
import Testing
@testable import PTReader

@Suite("EPUBReaderView")
struct EPUBReaderViewTests {
    @Test("load failure message falls back to the localized reader error")
    func localizedLoadFailureMessage() {
        let error = NSError(
            domain: "EPUBReaderViewTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Raw navigator failure"]
        )

        #expect(
            EPUBReaderView.loadFailureMessage(for: error)
                == AppLocalization.string(
                    "errors.reader.cannot_open",
                    value: "Cannot open this book."
                )
        )
    }
}
#endif
