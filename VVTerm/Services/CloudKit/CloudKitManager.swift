import Foundation
import os.log

struct CloudKitChanges {
    let servers: [Server]
    let workspaces: [Workspace]
    let deletedServerIDs: [UUID]
    let deletedWorkspaceIDs: [UUID]
    let isFullFetch: Bool

    static let empty = CloudKitChanges(
        servers: [],
        workspaces: [],
        deletedServerIDs: [],
        deletedWorkspaceIDs: [],
        isFullFetch: false
    )
}

@MainActor
final class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case error(String)
        case offline
        case disabled

        var description: String {
            switch self {
            case .idle: return String(localized: "Disabled")
            case .syncing: return String(localized: "Disabled")
            case .error(let message): return message
            case .offline: return String(localized: "Disabled")
            case .disabled: return String(localized: "Disabled")
            }
        }
    }

    @Published var syncStatus: SyncStatus = .disabled
    @Published var lastSyncDate: Date?
    @Published var isAvailable: Bool = false
    @Published var accountStatusDetail: String = String(localized: "Disabled")

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.vivy.VivyTerm", category: "Sync")

    private init() {
        logger.info("Cloud sync is disabled in this build")
    }

    func handleSyncToggle(_ enabled: Bool) {
        _ = enabled
        syncStatus = .disabled
        isAvailable = false
        accountStatusDetail = String(localized: "Disabled")
    }

    func fetchChanges() async throws -> CloudKitChanges { .empty }
    func saveServer(_ server: Server) async throws { _ = server }
    func deleteServer(_ server: Server) async throws { _ = server }
    func saveWorkspace(_ workspace: Workspace) async throws { _ = workspace }
    func deleteWorkspace(_ workspace: Workspace) async throws { _ = workspace }
    func subscribeToChanges() async { }
    func clearLocalChangeToken() { }

    func saveTerminalTheme(_ theme: TerminalTheme) async throws { _ = theme }
    func saveTerminalThemePreference(_ preference: TerminalThemePreference) async throws { _ = preference }
    func fetchTerminalThemes() async throws -> [TerminalTheme] { [] }
    func fetchTerminalThemePreference() async throws -> TerminalThemePreference? { nil }
    func syncTerminalAccessoryProfile(_ snapshot: TerminalAccessoryProfileSnapshot) async throws -> TerminalAccessoryProfileSnapshot { snapshot }
    func clearCloudData() async throws { }

    static func isSchemaError(_ error: Error) -> Bool {
        _ = error
        return false
    }
}
