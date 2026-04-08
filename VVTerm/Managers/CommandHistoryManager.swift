import Foundation
import os.log

// MARK: - Command History Entry

struct CommandHistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let command: String
    let timestamp: Date
    let serverId: UUID
    let sessionId: UUID?
    let exitCode: Int?
    let duration: TimeInterval?

    init(
        id: UUID = UUID(),
        command: String,
        timestamp: Date = Date(),
        serverId: UUID,
        sessionId: UUID? = nil,
        exitCode: Int? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.command = command
        self.timestamp = timestamp
        self.serverId = serverId
        self.sessionId = sessionId
        self.exitCode = exitCode
        self.duration = duration
    }
}

// MARK: - Command History Manager

@MainActor
final class CommandHistoryManager: ObservableObject {
    static let shared = CommandHistoryManager()

    @Published private(set) var history: [CommandHistoryEntry] = []

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.vivy.VivyTerm", category: "CommandHistory")
    private let storageKey = "com.vivy.vvterm.commandHistory"
    private let maxHistorySize = 10000 // Keep last 10k commands

    private init() {
        loadHistory()
    }

    // MARK: - Storage

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CommandHistoryEntry].self, from: data) else {
            logger.info("No command history found or failed to decode")
            return
        }

        history = decoded
        logger.info("Loaded \(decoded.count) command history entries")
    }

    private func saveHistory() {
        // Trim to max size
        if history.count > maxHistorySize {
            history = Array(history.suffix(maxHistorySize))
        }

        guard let data = try? JSONEncoder().encode(history) else {
            logger.error("Failed to encode command history")
            return
        }

        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: - Add Commands

    func addCommand(
        _ command: String,
        serverId: UUID,
        sessionId: UUID? = nil,
        exitCode: Int? = nil,
        duration: TimeInterval? = nil
    ) {
        let entry = CommandHistoryEntry(
            command: command,
            serverId: serverId,
            sessionId: sessionId,
            exitCode: exitCode,
            duration: duration
        )

        history.append(entry)
        saveHistory()
        logger.debug("Added command to history: \(command)")
    }

    // MARK: - Query History

    func historyForServer(_ serverId: UUID, limit: Int? = nil) -> [CommandHistoryEntry] {
        let filtered = history.filter { $0.serverId == serverId }
            .sorted { $0.timestamp > $1.timestamp }

        if let limit = limit {
            return Array(filtered.prefix(limit))
        }
        return filtered
    }

    func historyForSession(_ sessionId: UUID) -> [CommandHistoryEntry] {
        history.filter { $0.sessionId == sessionId }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func recentHistory(limit: Int = 100) -> [CommandHistoryEntry] {
        Array(history.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    func searchHistory(query: String, serverId: UUID? = nil) -> [CommandHistoryEntry] {
        var filtered = history

        if let serverId = serverId {
            filtered = filtered.filter { $0.serverId == serverId }
        }

        let lowercased = query.lowercased()
        return filtered
            .filter { $0.command.lowercased().contains(lowercased) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func uniqueCommands(forServer serverId: UUID, limit: Int = 50) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for entry in history.reversed() where entry.serverId == serverId {
            if !seen.contains(entry.command) {
                seen.insert(entry.command)
                result.append(entry.command)
                if result.count >= limit {
                    break
                }
            }
        }

        return result.reversed()
    }

    // MARK: - Statistics

    func commandCount(forServer serverId: UUID) -> Int {
        history.filter { $0.serverId == serverId }.count
    }

    func mostUsedCommands(forServer serverId: UUID, limit: Int = 10) -> [(command: String, count: Int)] {
        let filtered = history.filter { $0.serverId == serverId }

        var commandCounts: [String: Int] = [:]
        for entry in filtered {
            commandCounts[entry.command, default: 0] += 1
        }

        return commandCounts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (command: $0.key, count: $0.value) }
    }

    // MARK: - Clear History

    func clearHistory(forServer serverId: UUID) {
        history.removeAll { $0.serverId == serverId }
        saveHistory()
        logger.info("Cleared command history for server \(serverId)")
    }

    func clearAllHistory() {
        history.removeAll()
        saveHistory()
        logger.info("Cleared all command history")
    }

    func clearOldHistory(olderThan days: Int) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        history.removeAll { $0.timestamp < cutoffDate }
        saveHistory()
        logger.info("Cleared command history older than \(days) days")
    }
}
