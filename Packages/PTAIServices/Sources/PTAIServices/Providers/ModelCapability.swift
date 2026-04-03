import Foundation

public enum ModelCapability: String, Sendable, CaseIterable {
    case chat, vision, toolCalling, thinking, streaming
}
