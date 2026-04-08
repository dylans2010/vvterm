import Foundation

enum TranscriptionProvider: String, CaseIterable, Identifiable {
    case system

    var id: String { rawValue }
    var displayName: String { String(localized: "System") }
}

struct TranscriptionSettingsKeys {
    static let provider = "transcriptionProvider"
}

struct TranscriptionSettingsDefaults {
    static let provider: TranscriptionProvider = .system
}

struct TranscriptionSettingsStore {
    static func currentProvider() -> TranscriptionProvider { .system }
    static func currentWhisperModelId() -> String { "" }
    static func currentParakeetModelId() -> String { "" }
}
