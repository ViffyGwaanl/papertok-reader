import Testing
@testable import PTAIServices

@Suite("EmbeddingError")
struct EmbeddingServiceTests {
    @Test("embedding errors use localized or friendly fallback descriptions")
    func localizedEmbeddingErrors() {
        #expect(
            EmbeddingError.authenticationFailed("No API key available for embeddings").errorDescription
                == AppLocalization.string("errors.ai.no_api_key")
        )
        #expect(
            EmbeddingError.rateLimited.errorDescription
                == AppLocalization.string("errors.ai.rate_limited")
        )
        #expect(
            EmbeddingError.emptyResponse.errorDescription
                == AppLocalization.string(
                    "errors.ai.embeddings.empty_response",
                    value: "The embeddings service returned an empty response."
                )
        )
        #expect(
            EmbeddingError.decodingFailed("bad json").errorDescription
                == AppLocalization.string(
                    "errors.ai.embeddings.decoding_failed",
                    value: "Couldn't read the embeddings response."
                )
        )
        #expect(
            EmbeddingError.mismatchedCount(expected: 3, actual: 2).errorDescription
                == AppLocalization.format(
                    "errors.ai.embeddings.incomplete_response_format",
                    fallback: "The embeddings service returned %lld results for %lld requests.",
                    locale: .autoupdatingCurrent,
                    Int64(2),
                    Int64(3)
                )
        )
    }
}
