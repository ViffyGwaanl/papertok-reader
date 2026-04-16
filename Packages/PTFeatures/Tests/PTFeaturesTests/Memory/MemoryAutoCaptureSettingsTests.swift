import Foundation
import Testing
@testable import PTFeatures

@Suite("MemoryAutoCaptureSettings")
struct MemoryAutoCaptureSettingsTests {
    @Test("default confidence threshold is 0.5")
    func defaultConfidenceThreshold() {
        let defaults = UserDefaults(suiteName: "test-autocapture-\(UUID().uuidString)")!
        let value = defaults.double(forKey: "memory.auto_capture.confidence_threshold")
        // UserDefaults returns 0 for unset doubles
        #expect(value == 0.0)
    }

    @Test("toggles persist round-trip")
    func togglePersistence() {
        let suiteName = "test-autocapture-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "memory.auto_capture.ai_chat")
        defaults.set(true, forKey: "memory.auto_capture.reader_highlights")
        defaults.set(false, forKey: "memory.auto_capture.reader_notes")
        defaults.set(0.75, forKey: "memory.auto_capture.confidence_threshold")

        #expect(defaults.bool(forKey: "memory.auto_capture.ai_chat") == false)
        #expect(defaults.bool(forKey: "memory.auto_capture.reader_highlights") == true)
        #expect(defaults.bool(forKey: "memory.auto_capture.reader_notes") == false)
        #expect(defaults.double(forKey: "memory.auto_capture.confidence_threshold") == 0.75)
    }

    @Test("threshold round-trip at boundary values")
    func thresholdBoundary() {
        let suiteName = "test-autocapture-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        defaults.set(0.0, forKey: "memory.auto_capture.confidence_threshold")
        #expect(defaults.double(forKey: "memory.auto_capture.confidence_threshold") == 0.0)

        defaults.set(1.0, forKey: "memory.auto_capture.confidence_threshold")
        #expect(defaults.double(forKey: "memory.auto_capture.confidence_threshold") == 1.0)
    }
}
