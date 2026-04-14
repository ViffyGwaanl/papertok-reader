import Testing
@testable import PTAIServices

@Suite("SessionDigestService localization")
struct SessionDigestServiceTests {
    @Test("digest errors use localized or friendly fallback descriptions")
    func localizedDigestErrors() {
        #expect(
            SessionDigestService.DigestError.emptyMessages.errorDescription
                == AppLocalization.string(
                    "errors.memory.digest.no_messages",
                    value: "No messages are available to summarize."
                )
        )
        #expect(
            SessionDigestService.DigestError.providerReturnedEmpty.errorDescription
                == AppLocalization.string("errors.ai.no_response")
        )
        #expect(
            SessionDigestService.DigestError.memoryDirectoryUnavailable.errorDescription
                == AppLocalization.string(
                    "errors.memory.digest.directory_unavailable",
                    value: "Couldn't access the memory folder."
                )
        )
    }
}
