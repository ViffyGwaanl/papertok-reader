import SwiftUI
import PTNetworking
import PTUI

/// Full-height paper card with image, gradient overlay, title, extract, and like button.
struct PaperCardView: View {
    let card: PaperTokCard
    let isLiked: Bool
    let onLike: () -> Void
    let onTap: () -> Void

    @State private var currentImageIndex = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                imageLayer(size: geo.size)

                // Gradient overlay for text readability
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.7)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: geo.size.height * 0.55)

                textOverlay
            }
        }
        .background(Morandi.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    // MARK: - Image Layer

    @ViewBuilder
    private func imageLayer(size: CGSize) -> some View {
        if !card.thumbnails.isEmpty {
            TabView(selection: $currentImageIndex) {
                ForEach(card.thumbnails.indices, id: \.self) { index in
                    cachedImage(urlString: card.thumbnails[index], size: size)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .frame(height: size.height)
        } else if let thumbURL = card.thumbnailURL {
            cachedImage(urlString: thumbURL, size: size)
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            LinearGradient(
                colors: [Morandi.accent.opacity(0.3), Morandi.background],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private func cachedImage(urlString: String, size: CGSize) -> some View {
        CachedAsyncImage(
            url: URL(string: urlString),
            content: { image in
                image.resizable().scaledToFill()
            },
            placeholder: {
                placeholderImage
            },
            failure: { _ in
                placeholderImage
            }
        )
    }

    private var placeholderImage: some View {
        Morandi.divider
            .overlay(
                Image(systemName: "doc.text.image")
                    .font(.largeTitle)
                    .foregroundStyle(Morandi.tertiaryText)
            )
    }

    // MARK: - Text Overlay

    private var textOverlay: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Spacer()

            // Image page indicators
            if card.thumbnails.count > 1 {
                HStack(spacing: AppSpacing.xs) {
                    ForEach(card.thumbnails.indices, id: \.self) { i in
                        Circle()
                            .fill(i == currentImageIndex ? Color.white : Color.white.opacity(0.4))
                            .frame(width: 6, height: 6)
                    }
                }
            }

            Text(card.bestTitle)
                .font(AppTypography.title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(3)

            if !card.extract.isEmpty {
                Text(card.extract)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(4)
            }

            HStack {
                if let day = card.day {
                    Text(day)
                        .font(AppTypography.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Button(action: onLike) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(AppTypography.title3)
                        .foregroundStyle(isLiked ? Morandi.accent : .white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.bottom, AppSpacing.xxl)
    }
}
