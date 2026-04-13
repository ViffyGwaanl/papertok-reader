import SwiftUI
import PTCore
import PTUI

/// Full sheet for excerpt operations: save, share as text, share as image card, copy.
struct ExcerptMenuSheet: View {
    let selectedText: String
    let bookTitle: String
    let author: String
    let chapterTitle: String
    let onSaveToNotes: () -> Void
    let onDismiss: () -> Void

    @State private var renderedImage: ImageWrapper?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    excerptCard

                    actionButtons

                    if let renderedImage {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("reader.image_preview")
                                .font(AppTypography.caption.weight(.semibold))
                                .foregroundStyle(Morandi.secondaryText)

                            renderedImage.image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                                .shadow(
                                    color: Morandi.shadow,
                                    radius: AppSpacing.shadowRadius
                                )
                        }
                    }
                }
                .padding(AppSpacing.lg)
            }
            .background(Morandi.background)
            .navigationTitle(String(localized: "reader.excerpt"))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close"), action: onDismiss)
                        .foregroundStyle(Morandi.secondaryText)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Excerpt Card

    private var excerptCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if !chapterTitle.isEmpty {
                Text(chapterTitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
            }

            Text(selectedText)
                .font(AppTypography.body)
                .foregroundStyle(Morandi.primaryText)
                .textSelection(.enabled)

            HStack(spacing: AppSpacing.xs) {
                Text("--")
                    .foregroundStyle(Morandi.tertiaryText)
                Text(bookTitle)
                    .font(AppTypography.caption.italic())
                    .foregroundStyle(Morandi.secondaryText)
                if !author.isEmpty {
                    Text("by \(author)")
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                .fill(Morandi.cardBackground)
        )
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: AppSpacing.sm) {
            Button {
                onSaveToNotes()
            } label: {
                Label(String(localized: "reader.save_to_notes"), systemImage: "bookmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Morandi.accent)

            ShareLink(item: shareText) {
                Label(String(localized: "reader.share_as_text"), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Morandi.accent)

            Button {
                renderImageCard()
            } label: {
                Label(String(localized: "reader.generate_image_card"), systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Morandi.accent)

            if let renderedImage {
                ShareLink(
                    item: renderedImage,
                    preview: SharePreview("Excerpt from \(bookTitle)", image: renderedImage)
                ) {
                    Label(String(localized: "reader.share_image_card"), systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Morandi.accent)
            }

            Button {
                copyToClipboard()
            } label: {
                Label(String(localized: "common.copy"), systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Morandi.accent)
        }
    }

    // MARK: - Helpers

    private var shareText: String {
        var text = "\"\(selectedText)\""
        if !bookTitle.isEmpty {
            text += "\n-- \(bookTitle)"
        }
        if !author.isEmpty {
            text += ", \(author)"
        }
        return text
    }

    private func copyToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = shareText
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shareText, forType: .string)
        #endif
    }

    @MainActor
    private func renderImageCard() {
        let cardView = ExcerptImageCard(
            text: selectedText,
            bookTitle: bookTitle,
            author: author
        )

        let renderer = ImageRenderer(content: cardView.frame(width: 600))
        renderer.scale = 2.0

        #if os(iOS)
        if let uiImage = renderer.uiImage {
            renderedImage = ImageWrapper(platformImage: uiImage)
        }
        #else
        if let nsImage = renderer.nsImage {
            renderedImage = ImageWrapper(platformImage: nsImage)
        }
        #endif
    }
}

// MARK: - Image Card View

/// A view rendered to an image for sharing excerpts as styled cards.
private struct ExcerptImageCard: View {
    let text: String
    let bookTitle: String
    let author: String

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "quote.opening")
                .font(.system(size: 32))
                .foregroundStyle(Color(hex: "8FA68A").opacity(0.4))

            Text(text)
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundStyle(Color(hex: "343434"))
                .lineSpacing(8)

            HStack(spacing: 4) {
                Rectangle()
                    .fill(Color(hex: "8FA68A"))
                    .frame(width: 24, height: 2)

                Text(bookTitle)
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(Color(hex: "8A8A8E"))

                if !author.isEmpty {
                    Text("by \(author)")
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(Color(hex: "B0B0B4"))
                }
            }
        }
        .padding(40)
        .background(
            LinearGradient(
                colors: [Color(hex: "FAF8F5"), Color(hex: "F0EDE8")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

// MARK: - Image Wrapper for ShareLink

struct ImageWrapper: Transferable {
    #if os(iOS)
    let platformImage: UIImage
    var image: Image { Image(uiImage: platformImage) }
    #else
    let platformImage: NSImage
    var image: Image { Image(nsImage: platformImage) }
    #endif

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { wrapper in
            #if os(iOS)
            guard let data = wrapper.platformImage.pngData() else {
                throw CocoaError(.fileWriteUnknown)
            }
            return data
            #else
            guard let tiffData = wrapper.platformImage.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiffData),
                  let data = rep.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return data
            #endif
        }
    }
}
