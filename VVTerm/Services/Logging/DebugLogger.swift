import Foundation
import os.log

// MARK: - Debug Log Entry

struct DebugLogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let category: String
    let level: LogLevel
    let message: String
    let file: String?
    let function: String?
    let line: Int?
    let metadata: [String: String]?

    enum LogLevel: String, Codable, CaseIterable {
        case debug
        case info
        case warning
        case error
        case critical

        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            case .critical: return .fault
            }
        }

        var displayName: String {
            rawValue.capitalized
        }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: String,
        level: LogLevel,
        message: String,
        file: String? = nil,
        function: String? = nil,
        line: Int? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.level = level
        self.message = message
        self.file = file
        self.function = function
        self.line = line
        self.metadata = metadata
    }
}

// MARK: - Debug Logger

@MainActor
final class DebugLogger: ObservableObject {
    static let shared = DebugLogger()

    @Published private(set) var logs: [DebugLogEntry] = []
    @Published var verboseMode: Bool = false {
        didSet {
            UserDefaults.standard.set(verboseMode, forKey: verboseModeKey)
        }
    }
    @Published var enabledCategories: Set<String> = [] {
        didSet {
            if let data = try? JSONEncoder().encode(Array(enabledCategories)) {
                UserDefaults.standard.set(data, forKey: categoriesKey)
            }
        }
    }

    private let logger: Logger
    private let storageKey = "com.vivy.vvterm.debugLogs"
    private let verboseModeKey = "com.vivy.vvterm.debugVerbose"
    private let categoriesKey = "com.vivy.vvterm.debugCategories"
    private let maxLogsInMemory = 2000
    private let maxLogsOnDisk = 10000

    private init() {
        self.logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.vivy.VivyTerm", category: "DebugLogger")

        // Load settings
        verboseMode = UserDefaults.standard.bool(forKey: verboseModeKey)
        if let data = UserDefaults.standard.data(forKey: categoriesKey),
           let categories = try? JSONDecoder().decode([String].self, from: data) {
            enabledCategories = Set(categories)
        }

        loadLogs()
    }

    // MARK: - Storage

    private func loadLogs() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([DebugLogEntry].self, from: data) else {
            logger.info("No debug logs found")
            return
        }

        logs = Array(decoded.suffix(maxLogsInMemory))
        logger.info("Loaded \(logs.count) debug log entries")
    }

    private func saveLogs() {
        let logsToSave = Array(logs.suffix(maxLogsOnDisk))

        guard let data = try? JSONEncoder().encode(logsToSave) else {
            logger.error("Failed to encode debug logs")
            return
        }

        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: - Logging

    func log(
        _ level: DebugLogEntry.LogLevel,
        category: String,
        message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        metadata: [String: String]? = nil
    ) {
        // Skip if not in verbose mode and level is debug
        if !verboseMode && level == .debug {
            return
        }

        // Skip if category filtering is enabled and this category is not enabled
        if !enabledCategories.isEmpty && !enabledCategories.contains(category) {
            return
        }

        let entry = DebugLogEntry(
            category: category,
            level: level,
            message: message,
            file: (file as NSString).lastPathComponent,
            function: function,
            line: line,
            metadata: metadata
        )

        logs.append(entry)

        // Keep in-memory logs limited
        if logs.count > maxLogsInMemory {
            logs = Array(logs.suffix(maxLogsInMemory))
        }

        saveLogs()

        // Also log to OS logger
        logger.log(level: level.osLogType, "\(category): \(message)")
    }

    func debug(_ category: String, _ message: String, file: String = #file, function: String = #function, line: Int = #line, metadata: [String: String]? = nil) {
        log(.debug, category: category, message: message, file: file, function: function, line: line, metadata: metadata)
    }

    func info(_ category: String, _ message: String, file: String = #file, function: String = #function, line: Int = #line, metadata: [String: String]? = nil) {
        log(.info, category: category, message: message, file: file, function: function, line: line, metadata: metadata)
    }

    func warning(_ category: String, _ message: String, file: String = #file, function: String = #function, line: Int = #line, metadata: [String: String]? = nil) {
        log(.warning, category: category, message: message, file: file, function: function, line: line, metadata: metadata)
    }

    func error(_ category: String, _ message: String, file: String = #file, function: String = #function, line: Int = #line, metadata: [String: String]? = nil) {
        log(.error, category: category, message: message, file: file, function: function, line: line, metadata: metadata)
    }

    func critical(_ category: String, _ message: String, file: String = #file, function: String = #function, line: Int = #line, metadata: [String: String]? = nil) {
        log(.critical, category: category, message: message, file: file, function: function, line: line, metadata: metadata)
    }

    // MARK: - Specialized Logging

    func logSSHHandshake(server: Server, step: String, success: Bool, details: String? = nil) {
        var metadata: [String: String] = [
            "server": server.name,
            "host": server.host,
            "step": step,
            "success": "\(success)"
        ]
        if let details = details {
            metadata["details"] = details
        }

        log(
            success ? .info : .error,
            category: "SSH_Handshake",
            message: "[\(server.name)] \(step): \(success ? "SUCCESS" : "FAILED")\(details.map { " - \($0)" } ?? "")",
            metadata: metadata
        )
    }

    func logAuthentication(server: Server, method: AuthMethod, step: String, success: Bool, error: String? = nil) {
        var metadata: [String: String] = [
            "server": server.name,
            "host": server.host,
            "method": method.displayName,
            "step": step,
            "success": "\(success)"
        ]
        if let error = error {
            metadata["error"] = error
        }

        log(
            success ? .info : .error,
            category: "SSH_Auth",
            message: "[\(server.name)] Auth \(method.displayName) - \(step): \(success ? "SUCCESS" : "FAILED")\(error.map { " - \($0)" } ?? "")",
            metadata: metadata
        )
    }

    func logSFTPOperation(operation: String, path: String, server: Server, success: Bool, error: String? = nil) {
        var metadata: [String: String] = [
            "server": server.name,
            "operation": operation,
            "path": path,
            "success": "\(success)"
        ]
        if let error = error {
            metadata["error"] = error
        }

        log(
            success ? .info : .error,
            category: "SFTP",
            message: "[\(server.name)] \(operation) \(path): \(success ? "SUCCESS" : "FAILED")\(error.map { " - \($0)" } ?? "")",
            metadata: metadata
        )
    }

    func logCommand(command: String, server: Server, sessionId: UUID, exitCode: Int?, error: String? = nil) {
        var metadata: [String: String] = [
            "server": server.name,
            "session": sessionId.uuidString,
            "command": command
        ]
        if let exitCode = exitCode {
            metadata["exitCode"] = "\(exitCode)"
        }
        if let error = error {
            metadata["error"] = error
        }

        log(
            error == nil ? .info : .error,
            category: "Command",
            message: "[\(server.name)] \(command)\(exitCode.map { " [exit: \($0)]" } ?? "")\(error.map { " - \($0)" } ?? "")",
            metadata: metadata
        )
    }

    // MARK: - Query Logs

    func logs(
        category: String? = nil,
        level: DebugLogEntry.LogLevel? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        searchQuery: String? = nil
    ) -> [DebugLogEntry] {
        var filtered = logs

        if let category = category {
            filtered = filtered.filter { $0.category == category }
        }

        if let level = level {
            filtered = filtered.filter { $0.level == level }
        }

        if let startDate = startDate {
            filtered = filtered.filter { $0.timestamp >= startDate }
        }

        if let endDate = endDate {
            filtered = filtered.filter { $0.timestamp <= endDate }
        }

        if let searchQuery = searchQuery, !searchQuery.isEmpty {
            let lowercased = searchQuery.lowercased()
            filtered = filtered.filter {
                $0.message.lowercased().contains(lowercased) ||
                $0.category.lowercased().contains(lowercased)
            }
        }

        return filtered.sorted { $0.timestamp > $1.timestamp }
    }

    func recentLogs(limit: Int = 100) -> [DebugLogEntry] {
        Array(logs.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    func errorLogs() -> [DebugLogEntry] {
        logs.filter { $0.level == .error || $0.level == .critical }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func categories() -> [String] {
        Set(logs.map { $0.category }).sorted()
    }

    // MARK: - Export

    func exportToJSON() throws -> Data {
        try JSONEncoder().encode(logs)
    }

    func exportToText() -> String {
        logs.sorted { $0.timestamp > $1.timestamp }
            .map { formatLogForExport($0) }
            .joined(separator: "\n")
    }

    // MARK: - Clear Logs

    func clearLogs(olderThan days: Int) {
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return
        }

        let originalCount = logs.count
        logs.removeAll { $0.timestamp < cutoffDate }
        saveLogs()

        let removed = originalCount - logs.count
        logger.info("Cleared \(removed) debug logs older than \(days) days")
    }

    func clearAllLogs() {
        let count = logs.count
        logs.removeAll()
        saveLogs()
        logger.info("Cleared all \(count) debug logs")
    }

    func clearCategory(_ category: String) {
        let originalCount = logs.count
        logs.removeAll { $0.category == category }
        saveLogs()

        let removed = originalCount - logs.count
        logger.info("Cleared \(removed) debug logs for category \(category)")
    }

    // MARK: - Formatting

    private func formatLogForExport(_ log: DebugLogEntry) -> String {
        let dateFormatter = ISO8601DateFormatter()
        let timestamp = dateFormatter.string(from: log.timestamp)

        var parts: [String] = [timestamp, log.level.displayName, log.category, log.message]

        if let file = log.file, let function = log.function, let line = log.line {
            parts.append("[\(file):\(line) \(function)]")
        }

        if let metadata = log.metadata, !metadata.isEmpty {
            let metaString = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            parts.append("{\(metaString)}")
        }

        return parts.joined(separator: " | ")
    }
}
