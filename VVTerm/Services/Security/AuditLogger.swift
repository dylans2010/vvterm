import Foundation
import os.log

// MARK: - Audit Event Types

enum AuditEventType: String, Codable {
    case connectionAttempt
    case connectionSuccess
    case connectionFailure
    case disconnection
    case authenticationAttempt
    case authenticationSuccess
    case authenticationFailure
    case commandExecution
    case fileTransfer
    case fileUpload
    case fileDownload
    case fileDelete
    case portForwardingStarted
    case portForwardingStopped
    case credentialAccess
    case biometricUnlock
    case biometricUnlockFailure
    case sessionTimeout
    case appLockEnabled
    case appLockDisabled
    case configurationChange
    case suspiciousActivity
}

// MARK: - Audit Event

struct AuditEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let eventType: AuditEventType
    let serverId: UUID?
    let serverName: String?
    let username: String?
    let host: String?
    let port: Int?
    let details: String?
    let success: Bool
    let errorMessage: String?
    let sessionId: UUID?
    let ipAddress: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        eventType: AuditEventType,
        serverId: UUID? = nil,
        serverName: String? = nil,
        username: String? = nil,
        host: String? = nil,
        port: Int? = nil,
        details: String? = nil,
        success: Bool = true,
        errorMessage: String? = nil,
        sessionId: UUID? = nil,
        ipAddress: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.eventType = eventType
        self.serverId = serverId
        self.serverName = serverName
        self.username = username
        self.host = host
        self.port = port
        self.details = details
        self.success = success
        self.errorMessage = errorMessage
        self.sessionId = sessionId
        self.ipAddress = ipAddress
    }
}

// MARK: - Audit Logger

@MainActor
final class AuditLogger: ObservableObject {
    static let shared = AuditLogger()

    @Published private(set) var events: [AuditEvent] = []
    @Published var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: auditEnabledKey)
            if isEnabled {
                logger.info("Audit logging enabled")
            } else {
                logger.warning("Audit logging disabled")
            }
        }
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.vivy.VivyTerm", category: "AuditLogger")
    private let storageKey = "com.vivy.vvterm.auditLog"
    private let auditEnabledKey = "com.vivy.vvterm.auditEnabled"
    private let maxEventsInMemory = 5000
    private let maxEventsOnDisk = 50000

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: auditEnabledKey)
        loadEvents()
    }

    // MARK: - Storage

    private func loadEvents() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([AuditEvent].self, from: data) else {
            logger.info("No audit log found")
            return
        }

        events = Array(decoded.suffix(maxEventsInMemory))
        logger.info("Loaded \(self.events.count) audit events")
    }

    private func saveEvents() {
        // Keep only the most recent events
        let eventsToSave = Array(events.suffix(maxEventsOnDisk))

        guard let data = try? JSONEncoder().encode(eventsToSave) else {
            logger.error("Failed to encode audit events")
            return
        }

        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: - Log Events

    func log(
        _ eventType: AuditEventType,
        serverId: UUID? = nil,
        serverName: String? = nil,
        username: String? = nil,
        host: String? = nil,
        port: Int? = nil,
        details: String? = nil,
        success: Bool = true,
        errorMessage: String? = nil,
        sessionId: UUID? = nil
    ) {
        guard isEnabled else { return }

        let event = AuditEvent(
            eventType: eventType,
            serverId: serverId,
            serverName: serverName,
            username: username,
            host: host,
            port: port,
            details: details,
            success: success,
            errorMessage: errorMessage,
            sessionId: sessionId
        )

        events.append(event)

        // Keep in-memory events limited
        if events.count > maxEventsInMemory {
            events = Array(events.suffix(maxEventsInMemory))
        }

        saveEvents()

        // Log to system logger as well
        let message = formatEventForLog(event)
        if success {
            logger.info("\(message, privacy: .public)")
        } else {
            logger.warning("\(message, privacy: .public)")
        }
    }

    func logConnectionAttempt(server: Server, sessionId: UUID) {
        log(
            .connectionAttempt,
            serverId: server.id,
            serverName: server.name,
            username: server.username,
            host: server.host,
            port: server.port,
            sessionId: sessionId
        )
    }

    func logConnectionSuccess(server: Server, sessionId: UUID) {
        log(
            .connectionSuccess,
            serverId: server.id,
            serverName: server.name,
            username: server.username,
            host: server.host,
            port: server.port,
            sessionId: sessionId
        )
    }

    func logConnectionFailure(server: Server, error: String, sessionId: UUID) {
        log(
            .connectionFailure,
            serverId: server.id,
            serverName: server.name,
            username: server.username,
            host: server.host,
            port: server.port,
            success: false,
            errorMessage: error,
            sessionId: sessionId
        )
    }

    func logAuthenticationAttempt(server: Server, method: AuthMethod) {
        log(
            .authenticationAttempt,
            serverId: server.id,
            serverName: server.name,
            username: server.username,
            host: server.host,
            port: server.port,
            details: "Method: \(method.displayName)"
        )
    }

    func logAuthenticationSuccess(server: Server, method: AuthMethod) {
        log(
            .authenticationSuccess,
            serverId: server.id,
            serverName: server.name,
            username: server.username,
            host: server.host,
            port: server.port,
            details: "Method: \(method.displayName)"
        )
    }

    func logAuthenticationFailure(server: Server, method: AuthMethod, error: String) {
        log(
            .authenticationFailure,
            serverId: server.id,
            serverName: server.name,
            username: server.username,
            host: server.host,
            port: server.port,
            details: "Method: \(method.displayName)",
            success: false,
            errorMessage: error
        )
    }

    func logCommandExecution(command: String, server: Server, sessionId: UUID) {
        log(
            .commandExecution,
            serverId: server.id,
            serverName: server.name,
            username: server.username,
            host: server.host,
            port: server.port,
            details: "Command: \(command)",
            sessionId: sessionId
        )
    }

    func logFileTransfer(operation: String, path: String, server: Server, success: Bool, error: String? = nil) {
        log(
            .fileTransfer,
            serverId: server.id,
            serverName: server.name,
            username: server.username,
            host: server.host,
            port: server.port,
            details: "\(operation): \(path)",
            success: success,
            errorMessage: error
        )
    }

    func logBiometricUnlock(success: Bool, error: String? = nil) {
        log(
            success ? .biometricUnlock : .biometricUnlockFailure,
            success: success,
            errorMessage: error
        )
    }

    // MARK: - Query Events

    func events(
        forServer serverId: UUID? = nil,
        eventType: AuditEventType? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        successOnly: Bool? = nil
    ) -> [AuditEvent] {
        var filtered = events

        if let serverId = serverId {
            filtered = filtered.filter { $0.serverId == serverId }
        }

        if let eventType = eventType {
            filtered = filtered.filter { $0.eventType == eventType }
        }

        if let startDate = startDate {
            filtered = filtered.filter { $0.timestamp >= startDate }
        }

        if let endDate = endDate {
            filtered = filtered.filter { $0.timestamp <= endDate }
        }

        if let successOnly = successOnly {
            filtered = filtered.filter { $0.success == successOnly }
        }

        return filtered.sorted { $0.timestamp > $1.timestamp }
    }

    func recentEvents(limit: Int = 100) -> [AuditEvent] {
        Array(events.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    func failedEvents(limit: Int? = nil) -> [AuditEvent] {
        let failed = events.filter { !$0.success }
            .sorted { $0.timestamp > $1.timestamp }

        if let limit = limit {
            return Array(failed.prefix(limit))
        }
        return failed
    }

    func suspiciousActivity() -> [AuditEvent] {
        events.filter { $0.eventType == .suspiciousActivity }
            .sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Export

    func exportToJSON() throws -> Data {
        try JSONEncoder().encode(events)
    }

    func exportToText() -> String {
        events.sorted { $0.timestamp > $1.timestamp }
            .map { formatEventForExport($0) }
            .joined(separator: "\n")
    }

    // MARK: - Clear Events

    func clearEvents(olderThan days: Int) {
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return
        }

        let originalCount = events.count
        events.removeAll { $0.timestamp < cutoffDate }
        saveEvents()

        let removed = originalCount - events.count
        logger.info("Cleared \(removed) audit events older than \(days) days")
    }

    func clearAllEvents() {
        let count = events.count
        events.removeAll()
        saveEvents()
        logger.warning("Cleared all \(count) audit events")
    }

    // MARK: - Formatting

    private func formatEventForLog(_ event: AuditEvent) -> String {
        var parts: [String] = []
        parts.append("[\(event.eventType.rawValue)]")

        if let serverName = event.serverName {
            parts.append("server=\(serverName)")
        }

        if let username = event.username, let host = event.host {
            parts.append("user=\(username)@\(host)")
        }

        if let details = event.details {
            parts.append(details)
        }

        if !event.success, let error = event.errorMessage {
            parts.append("error=\(error)")
        }

        return parts.joined(separator: " ")
    }

    private func formatEventForExport(_ event: AuditEvent) -> String {
        let dateFormatter = ISO8601DateFormatter()
        let timestamp = dateFormatter.string(from: event.timestamp)

        var parts: [String] = [timestamp, event.eventType.rawValue]

        if let serverName = event.serverName {
            parts.append("server:\(serverName)")
        }

        if let username = event.username {
            parts.append("user:\(username)")
        }

        if let host = event.host {
            parts.append("host:\(host)")
        }

        if let port = event.port {
            parts.append("port:\(port)")
        }

        if let details = event.details {
            parts.append("details:\(details)")
        }

        parts.append("success:\(event.success)")

        if let error = event.errorMessage {
            parts.append("error:\(error)")
        }

        return parts.joined(separator: " | ")
    }
}
