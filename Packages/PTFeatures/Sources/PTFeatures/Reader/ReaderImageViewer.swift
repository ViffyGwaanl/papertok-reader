import SwiftUI
import PTReader
import PTUI

#if canImport(UIKit)
import UIKit
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias PlatformImage = NSImage
#endif

public struct ReaderImageViewer: View {
    public let asset: ReaderImageAsset
    public let bookTitle: String
    public let chapterTitle: String?
    public let onClose: () -> Void
    public let onAnalyze: () -> Void

    @State private var zoomScale: CGFloat = 1
    @State private var committedZoomScale: CGFloat = 1
    @State private var dragOffset: CGSize = .zero
    @State private var committedDragOffset: CGSize = .zero
    @State private var exportURL: URL?
    @State private var exportError: String?

    public init(
        asset: ReaderImageAsset,
        bookTitle: String,
        chapterTitle: String? = nil,
        onClose: @escaping () -> Void,
        onAnalyze: @escaping () -> Void
    ) {
        self.asset = asset
        self.bookTitle = bookTitle
        self.chapterTitle = chapterTitle
        self.onClose = onClose
        self.onAnalyze = onAnalyze
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let platformImage = PlatformImage(data: asset.data) {
                GeometryReader { geometry in
                    imageView(platformImage, in: geometry.size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView(
                    "Unable to Load Image",
                    systemImage: "photo",
                    description: Text("reader.image_not_decoded")
                )
                .foregroundStyle(.white)
            }

            overlayChrome
        }
        .task {
            do {
                exportURL = try ReaderImageFileStore.temporaryFileURL(for: asset)
            } catch {
                exportError = error.localizedDescription
            }
        }
        .alert("reader.unable_prepare_image", isPresented: exportErrorPresentedBinding) {
            Button(String(localized: "common.ok")) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    @ViewBuilder
    private func imageView(_ platformImage: PlatformImage, in size: CGSize) -> some View {
        renderedImage(platformImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(zoomScale)
            .offset(dragOffset)
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    if zoomScale > 1.05 {
                        resetZoom()
                    } else {
                        zoomScale = 2
                        committedZoomScale = 2
                    }
                }
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        zoomScale = min(max(committedZoomScale * value.magnification, 1), 4)
                    }
                    .onEnded { _ in
                        committedZoomScale = zoomScale
                        if zoomScale <= 1.01 {
                            resetZoom()
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard zoomScale > 1.01 else { return }
                        dragOffset = CGSize(
                            width: committedDragOffset.width + value.translation.width,
                            height: committedDragOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        committedDragOffset = dragOffset
                    }
            )
            .frame(width: size.width, height: size.height)
    }

    private func renderedImage(_ platformImage: PlatformImage) -> Image {
#if canImport(UIKit)
        Image(uiImage: platformImage)
#elseif canImport(AppKit)
        Image(nsImage: platformImage)
#endif
    }

    private var overlayChrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.sm) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)

                Spacer()

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.headline)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .accessibilityLabel(String(localized: "common.share_image"))
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.lg)

            Spacer()

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(bookTitle)
                    .font(AppTypography.headline)
                    .foregroundStyle(.white)

                if let chapterTitle, chapterTitle.isEmpty == false {
                    Text(chapterTitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }

                if let title = asset.title {
                    Text(title)
                        .font(AppTypography.body)
                        .foregroundStyle(.white)
                } else if let altText = asset.altText {
                    Text(altText)
                        .font(AppTypography.body)
                        .foregroundStyle(.white)
                }

                HStack(spacing: AppSpacing.sm) {
                    Button(String(localized: "reader.analyze_with_ai"), action: onAnalyze)
                        .buttonStyle(.borderedProminent)
                        .tint(Morandi.accent)

                    Button(String(localized: "reader.fit_image")) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            resetZoom()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
        }
    }

    private var exportErrorPresentedBinding: Binding<Bool> {
        Binding(
            get: { exportError?.isEmpty == false },
            set: { isPresented in
                if isPresented == false {
                    exportError = nil
                }
            }
        )
    }

    private func resetZoom() {
        zoomScale = 1
        committedZoomScale = 1
        dragOffset = .zero
        committedDragOffset = .zero
    }
}
