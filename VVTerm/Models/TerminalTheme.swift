import Foundation

struct TerminalTheme: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var content: String
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        content: String,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var isDeleted: Bool {
        deletedAt != nil
    }
}

struct TerminalThemePreference: Codable, Equatable {
    static let recordName = "terminal-theme-preference.v1"

    var darkThemeName: String
    var lightThemeName: String
    var usePerAppearanceTheme: Bool
    var updatedAt: Date
}
