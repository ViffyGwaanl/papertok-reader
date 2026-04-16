import Testing
@testable import PTFeatures

struct ReaderAIPanelStateTests {
    @Test func toggleFlipsIsOpen() async {
        await MainActor.run {
            let state = ReaderAIPanelState()
            #expect(state.isOpen == false)
            state.toggle()
            #expect(state.isOpen == true)
        }
    }

    @Test func panelWidthClamps() async {
        await MainActor.run {
            let state = ReaderAIPanelState(panelWidth: 200)
            #expect(state.clampedWidth == 320)
            state.panelWidth = 800
            #expect(state.clampedWidth == 600)
        }
    }

    @Test func autoModeReturnsSheetBelowThreshold() async {
        await MainActor.run {
            let state = ReaderAIPanelState()
            #expect(state.resolvedPresentationMode(containerWidth: 500) == .sheet)
            #expect(state.resolvedPresentationMode(containerWidth: 800) == .sidePanel)
        }
    }

    @Test func dockSideDefaultsToTrailing() async {
        await MainActor.run {
            let state = ReaderAIPanelState()
            #expect(state.dockSide == .trailing)
        }
    }

    @Test func widthDefaultsTo380() async {
        await MainActor.run {
            let state = ReaderAIPanelState()
            #expect(state.panelWidth == 380)
        }
    }
}
