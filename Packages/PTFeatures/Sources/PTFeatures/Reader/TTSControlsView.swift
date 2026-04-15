import SwiftUI
import PTReader
import PTUI

#if canImport(AVFoundation)
import AVFoundation

/// Legacy entry point kept for backward compatibility with existing reader
/// call sites. Delegates to the new `TTSFloatingActionButton`.
public struct TTSFabButton: View {
    @Bindable var ttsService: TTSService
    let currentText: () -> String?
    let chapterTitle: String?

    public init(
        ttsService: TTSService,
        currentText: @escaping () -> String?,
        chapterTitle: String? = nil
    ) {
        self.ttsService = ttsService
        self.currentText = currentText
        self.chapterTitle = chapterTitle
    }

    public var body: some View {
        TTSFloatingActionButton(
            service: ttsService,
            chapterTitle: chapterTitle,
            currentText: currentText
        )
    }
}

/// Legacy sheet type. Thin wrapper around the new expanded controls.
public struct TTSControlsSheet: View {
    @Bindable var ttsService: TTSService
    let currentText: () -> String?

    public init(ttsService: TTSService, currentText: @escaping () -> String?) {
        self.ttsService = ttsService
        self.currentText = currentText
    }

    public var body: some View {
        TTSExpandedControlsSheet(service: ttsService, currentText: currentText)
    }
}
#endif
