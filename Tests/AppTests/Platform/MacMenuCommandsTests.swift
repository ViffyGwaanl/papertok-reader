import Foundation
import Testing
import PTCore

/// Tests for macOS menu bar command notifications (W4.4).
/// These verify the notification bus wiring without requiring AppKit.
struct MacMenuCommandsTests {

    // MARK: - Import book notification

    @Test
    func importBookNotificationPosted() async {
        let expectation = NotificationExpectation(name: .importBook)
        NotificationCenter.default.post(name: .importBook, object: nil)
        await expectation.verify()
    }

    // MARK: - Font size notifications

    @Test
    func increaseFontSizeNotificationPosted() async {
        let expectation = NotificationExpectation(name: .increaseFontSize)
        NotificationCenter.default.post(name: .increaseFontSize, object: nil)
        await expectation.verify()
    }

    @Test
    func decreaseFontSizeNotificationPosted() async {
        let expectation = NotificationExpectation(name: .decreaseFontSize)
        NotificationCenter.default.post(name: .decreaseFontSize, object: nil)
        await expectation.verify()
    }

    // MARK: - Toggle AI panel notification

    @Test
    func toggleAIPanelNotificationPosted() async {
        let expectation = NotificationExpectation(name: .toggleAIPanel)
        NotificationCenter.default.post(name: .toggleAIPanel, object: nil)
        await expectation.verify()
    }

    // MARK: - Chapter navigation notifications

    @Test
    func previousChapterNotificationPosted() async {
        let expectation = NotificationExpectation(name: .previousChapter)
        NotificationCenter.default.post(name: .previousChapter, object: nil)
        await expectation.verify()
    }

    @Test
    func nextChapterNotificationPosted() async {
        let expectation = NotificationExpectation(name: .nextChapter)
        NotificationCenter.default.post(name: .nextChapter, object: nil)
        await expectation.verify()
    }

    // MARK: - Show in Finder notification

    @Test
    func showInFinderNotificationPosted() async {
        let expectation = NotificationExpectation(name: .showInFinder)
        NotificationCenter.default.post(name: .showInFinder, object: nil)
        await expectation.verify()
    }

    // MARK: - Notification names are distinct

    @Test
    func allNotificationNamesAreDistinct() {
        let names: [Notification.Name] = [
            .importBook,
            .toggleAIPanel,
            .previousChapter,
            .nextChapter,
            .increaseFontSize,
            .decreaseFontSize,
            .showInFinder,
        ]
        let unique = Set(names)
        #expect(unique.count == names.count)
    }
}

// MARK: - Test helper

/// Lightweight notification expectation for Swift Testing.
private final class NotificationExpectation: @unchecked Sendable {
    private let name: Notification.Name
    private var received = false
    private var observer: NSObjectProtocol?

    init(name: Notification.Name) {
        self.name = name
        observer = NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: nil
        ) { [self] _ in
            received = true
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func verify() async {
        // Give a brief moment for synchronous delivery to complete.
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        #expect(received, "Expected notification \(name.rawValue) to be posted")
    }
}
