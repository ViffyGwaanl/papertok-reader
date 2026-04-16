import SwiftUI
import PTCore
import PTUI

#if canImport(UIKit)
import UIKit
typealias PaperPlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PaperPlatformImage = NSImage
#endif

/// URLCache + URLSession backed image loader used by the Papers feed and detail sheet.
///
/// Differs from SwiftUI's `AsyncImage` by:
/// - Sharing a process-wide `URLCache` (50MB memory / 100MB disk) so repeat views avoid network.
/// - Using `returnCacheDataElseLoad` so cached bytes are preferred over re-requests.
/// - Surfacing a dedicated failure phase with a `retry` closure for manual reload.
/// - Applying a 20s request timeout.
struct CachedAsyncImage<Content: View, Placeholder: View, Failure: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    let failure: (_ retry: @escaping () -> Void) -> Failure

    @State private var phase: Phase = .idle
    @State private var loadToken: UUID = UUID()

    enum Phase: Equatable {
        case idle
        case loading
        case success(PaperPlatformImage)
        case failed
    }

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failure: @escaping (_ retry: @escaping () -> Void) -> Failure
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        self.failure = failure
    }

    var body: some View {
        Group {
            switch phase {
            case .idle, .loading:
                placeholder()
            case .success(let image):
                #if canImport(UIKit)
                content(Image(uiImage: image))
                #elseif canImport(AppKit)
                content(Image(nsImage: image))
                #endif
            case .failed:
                failure(retry)
            }
        }
        .task(id: loadToken) {
            await load()
        }
        .onChange(of: url) { _, _ in
            phase = .idle
            loadToken = UUID()
        }
    }

    private func retry() {
        phase = .idle
        loadToken = UUID()
    }

    private func load() async {
        guard let url else {
            phase = .failed
            return
        }
        phase = .loading
        do {
            let request = PaperImageCache.makeRequest(url: url)
            let (data, response) = try await PaperImageCache.session.data(for: request)
            if Task.isCancelled { return }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                phase = .failed
                return
            }
            if let image = PaperPlatformImage(data: data) {
                phase = .success(image)
            } else {
                phase = .failed
            }
        } catch {
            if Task.isCancelled { return }
            phase = .failed
        }
    }
}

/// Process-wide URLSession + URLCache for paper thumbnail / carousel images.
enum PaperImageCache {
    static let cache: URLCache = {
        let memoryCapacity = 50 * 1024 * 1024
        let diskCapacity = 100 * 1024 * 1024
        return URLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            diskPath: "papertok_images"
        )
    }()

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    /// Build the URLRequest used by `CachedAsyncImage`. Exposed so tests can assert
    /// the timeout and cache policy without hitting the network.
    static func makeRequest(url: URL, timeout: TimeInterval = 20) -> URLRequest {
        URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: timeout)
    }
}

/// Failure overlay rendered when an image cannot load, with a retry button.
struct PaperImageFailureView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(Morandi.tertiaryText)
            Text(AppLocalization.string("papers.image.load_failed"))
                .font(AppTypography.caption)
                .foregroundStyle(Morandi.secondaryText)
                .multilineTextAlignment(.center)
            Button(AppLocalization.string("papers.image.retry"), action: retry)
                .font(AppTypography.caption)
                .buttonStyle(.bordered)
                .tint(Morandi.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Morandi.divider)
    }
}

/// Neutral placeholder (spinner on a Morandi background) while an image is loading.
struct PaperImageLoadingView: View {
    var body: some View {
        ZStack {
            Morandi.divider
            ProgressView().tint(Morandi.accent)
        }
    }
}
