import SwiftUI
import PTCore
import PTUI

/// A bottom page scrubber/slider for quick navigation in the reader.
/// Shows current page and total pages, with a draggable slider.
public struct ReaderPageSlider: View {
    @Binding public var currentPage: Int
    public let pageCount: Int
    public let onPageChange: (Int) -> Void

    @State private var sliderValue: Double = 0
    @State private var isDragging: Bool = false

    public init(
        currentPage: Binding<Int>,
        pageCount: Int,
        onPageChange: @escaping (Int) -> Void
    ) {
        self._currentPage = currentPage
        self.pageCount = pageCount
        self.onPageChange = onPageChange
    }

    public var body: some View {
        guard pageCount > 1 else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.md) {
                    Text("\(displayPage)")
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.primaryText)
                        .monospacedDigit()
                        .frame(width: 40, alignment: .leading)

                    Slider(
                        value: $sliderValue,
                        in: 0...Double(max(pageCount - 1, 1)),
                        step: 1
                    ) { editing in
                        isDragging = editing
                        if !editing {
                            let page = Int(sliderValue)
                            onPageChange(page)
                        }
                    }
                    .tint(Morandi.accent)

                    Text("\(pageCount)")
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.secondaryText)
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.sm)
            .onChange(of: currentPage) { _, newValue in
                guard !isDragging else { return }
                sliderValue = Double(newValue)
            }
            .onAppear {
                sliderValue = Double(currentPage)
            }
        )
    }

    private var displayPage: Int {
        isDragging ? Int(sliderValue) + 1 : currentPage + 1
    }
}
