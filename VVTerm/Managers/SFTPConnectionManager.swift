import Foundation
import os.log
import Combine

// MARK: - SFTP Models

struct SFTPDirectoryEntry: Identifiable, Hashable {
    enum EntryKind: String, Hashable {
        case directory
        case file
        case symlink
        case unknown
    }

    let id = UUID()
    let name: String
    let permissions: String
    let owner: String
    let group: String
    let size: String
    let modified: String
    let kind: EntryKind

    var numericPermissions: String {
        parsePermissionsToOctal(permissions)
    }

    private func parsePermissionsToOctal(_ perms: String) -> String {
        guard perms.count >= 10 else { return "644" }

        let chars = Array(perms)
        var result = ""

        for i in stride(from: 1, to: 10, by: 3) {
            var value = 0
            if chars[i] == "r" { value += 4 }
            if chars[i+1] == "w" { value += 2 }
            if chars[i+2] == "x" || chars[i+2] == "s" || chars[i+2] == "t" { value += 1 }
            result += "\(value)"
        }

        return result
    }
}

struct SFTPTransferProgress: Identifiable {
    let id = UUID()
    let fileName: String
    var totalBytes: Int64
    var transferredBytes: Int64
    let isUpload: Bool
    var isComplete: Bool = false
    var error: String?

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(transferredBytes) / Double(totalBytes)
    }
}

@MainActor
final class SFTPConnectionManager: ObservableObject {
    static let shared = SFTPConnectionManager()

    @Published private(set) var entriesByServer: [UUID: [SFTPDirectoryEntry]] = [:]
    @Published private(set) var currentPathByServer: [UUID: String] = [:]
    @Published private(set) var lastErrorByServer: [UUID: String] = [:]
    @Published private(set) var isLoadingByServer: [UUID: Bool] = [:]
    @Published private(set) var activeTransfers: [SFTPTransferProgress] = []

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.vivy.VivyTerm", category: "SFTP")

    private init() {}

    // MARK: - Directory Listing

    func refreshListing(for server: Server, credentials: ServerCredentials, path: String? = nil) async {
        isLoadingByServer[server.id] = true
        defer { isLoadingByServer[server.id] = false }

        let targetPath = normalized(path ?? currentPathByServer[server.id] ?? ".")
        logger.info("Refreshing SFTP listing for server=\(server.name, privacy: .public) path=\(targetPath, privacy: .private)")

        do {
            let snapshot = try await SSHConnectionOperationService.shared.withTemporaryConnection(server: server, credentials: credentials) { client in
                let pwd = try await client.execute("pwd")
                let resolvedPath = path ?? pwd.trimmingCharacters(in: .whitespacesAndNewlines)
                let escapedPath = Self.shellQuoted(self.normalized(resolvedPath.isEmpty ? "." : resolvedPath))
                let listOutput = try await client.execute("LC_ALL=C ls -la \(escapedPath)")
                return (resolvedPath, listOutput)
            }

            let parsedEntries = parseLSLA(snapshot.1)
            entriesByServer[server.id] = parsedEntries
            currentPathByServer[server.id] = normalized(snapshot.0)
            lastErrorByServer[server.id] = nil
            logger.info("SFTP listing loaded with \(parsedEntries.count) entries for server=\(server.name, privacy: .public)")
        } catch {
            let message = String(format: String(localized: "SFTP listing failed: %@"), error.localizedDescription)
            lastErrorByServer[server.id] = message
            logger.error("SFTP listing failed for server=\(server.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func navigateInto(_ entry: SFTPDirectoryEntry, for server: Server, credentials: ServerCredentials) async {
        guard entry.kind == .directory else { return }
        let base = currentPathByServer[server.id] ?? "."
        let nextPath = normalized((base as NSString).appendingPathComponent(entry.name))
        await refreshListing(for: server, credentials: credentials, path: nextPath)
    }

    func navigateUp(for server: Server, credentials: ServerCredentials) async {
        let current = normalized(currentPathByServer[server.id] ?? ".")
        let parent = (current as NSString).deletingLastPathComponent
        let resolved = parent.isEmpty ? "/" : parent
        await refreshListing(for: server, credentials: credentials, path: resolved)
    }

    // MARK: - File Operations

    func uploadFile(localPath: String, remotePath: String, server: Server, credentials: ServerCredentials) async throws {
        let fileName = (localPath as NSString).lastPathComponent
        let fileSize = try FileManager.default.attributesOfItem(atPath: localPath)[.size] as? Int64 ?? 0

        var progress = SFTPTransferProgress(
            fileName: fileName,
            totalBytes: fileSize,
            transferredBytes: 0,
            isUpload: true
        )
        activeTransfers.append(progress)

        defer {
            if let index = activeTransfers.firstIndex(where: { $0.id == progress.id }) {
                activeTransfers[index].isComplete = true
            }
        }

        do {
            try await SSHConnectionOperationService.shared.withTemporaryConnection(server: server, credentials: credentials) { client in
                let escapedRemote = Self.shellQuoted(remotePath)
                let escapedLocal = Self.shellQuoted(localPath)

                // For demo purposes, we'll use scp-like command
                // In production, would use proper SFTP protocol
                _ = try await client.execute("cat > \(escapedRemote) << 'VVTERM_EOF'\n\(try String(contentsOfFile: localPath))\nVVTERM_EOF")
            }

            if let index = activeTransfers.firstIndex(where: { $0.id == progress.id }) {
                activeTransfers[index].transferredBytes = fileSize
                activeTransfers[index].isComplete = true
            }

            logger.info("Uploaded file: \(fileName) to \(remotePath)")
            AuditLogger.shared.logFileTransfer(operation: "upload", path: remotePath, server: server, success: true)
        } catch {
            if let index = activeTransfers.firstIndex(where: { $0.id == progress.id }) {
                activeTransfers[index].error = error.localizedDescription
            }
            logger.error("Failed to upload file: \(error.localizedDescription)")
            AuditLogger.shared.logFileTransfer(operation: "upload", path: remotePath, server: server, success: false, error: error.localizedDescription)
            throw error
        }
    }

    func downloadFile(remotePath: String, localPath: String, server: Server, credentials: ServerCredentials) async throws {
        let fileName = (remotePath as NSString).lastPathComponent

        var progress = SFTPTransferProgress(
            fileName: fileName,
            totalBytes: 0, // Will be determined during download
            transferredBytes: 0,
            isUpload: false
        )
        activeTransfers.append(progress)

        defer {
            if let index = activeTransfers.firstIndex(where: { $0.id == progress.id }) {
                activeTransfers[index].isComplete = true
            }
        }

        do {
            try await SSHConnectionOperationService.shared.withTemporaryConnection(server: server, credentials: credentials) { client in
                let escapedRemote = Self.shellQuoted(remotePath)
                let content = try await client.execute("cat \(escapedRemote)")
                try content.write(toFile: localPath, atomically: true, encoding: .utf8)
            }

            let fileSize = try FileManager.default.attributesOfItem(atPath: localPath)[.size] as? Int64 ?? 0
            if let index = activeTransfers.firstIndex(where: { $0.id == progress.id }) {
                activeTransfers[index].totalBytes = fileSize
                activeTransfers[index].transferredBytes = fileSize
                activeTransfers[index].isComplete = true
            }

            logger.info("Downloaded file: \(fileName) to \(localPath)")
            AuditLogger.shared.logFileTransfer(operation: "download", path: remotePath, server: server, success: true)
        } catch {
            if let index = activeTransfers.firstIndex(where: { $0.id == progress.id }) {
                activeTransfers[index].error = error.localizedDescription
            }
            logger.error("Failed to download file: \(error.localizedDescription)")
            AuditLogger.shared.logFileTransfer(operation: "download", path: remotePath, server: server, success: false, error: error.localizedDescription)
            throw error
        }
    }

    func deleteFile(remotePath: String, server: Server, credentials: ServerCredentials) async throws {
        do {
            try await SSHConnectionOperationService.shared.withTemporaryConnection(server: server, credentials: credentials) { client in
                let escapedPath = Self.shellQuoted(remotePath)
                _ = try await client.execute("rm -f \(escapedPath)")
            }

            logger.info("Deleted file: \(remotePath)")
            AuditLogger.shared.logFileTransfer(operation: "delete", path: remotePath, server: server, success: true)
        } catch {
            logger.error("Failed to delete file: \(error.localizedDescription)")
            AuditLogger.shared.logFileTransfer(operation: "delete", path: remotePath, server: server, success: false, error: error.localizedDescription)
            throw error
        }
    }

    func renameFile(oldPath: String, newPath: String, server: Server, credentials: ServerCredentials) async throws {
        try await SSHConnectionOperationService.shared.withTemporaryConnection(server: server, credentials: credentials) { client in
            let escapedOld = Self.shellQuoted(oldPath)
            let escapedNew = Self.shellQuoted(newPath)
            _ = try await client.execute("mv \(escapedOld) \(escapedNew)")
        }

        logger.info("Renamed file: \(oldPath) -> \(newPath)")
        AuditLogger.shared.logFileTransfer(operation: "rename", path: "\(oldPath) -> \(newPath)", server: server, success: true)
    }

    func createDirectory(path: String, server: Server, credentials: ServerCredentials) async throws {
        try await SSHConnectionOperationService.shared.withTemporaryConnection(server: server, credentials: credentials) { client in
            let escapedPath = Self.shellQuoted(path)
            _ = try await client.execute("mkdir -p \(escapedPath)")
        }

        logger.info("Created directory: \(path)")
    }

    func changePermissions(path: String, permissions: String, server: Server, credentials: ServerCredentials) async throws {
        try await SSHConnectionOperationService.shared.withTemporaryConnection(server: server, credentials: credentials) { client in
            let escapedPath = Self.shellQuoted(path)
            _ = try await client.execute("chmod \(permissions) \(escapedPath)")
        }

        logger.info("Changed permissions: \(path) to \(permissions)")
        AuditLogger.shared.logFileTransfer(operation: "chmod", path: "\(path) (\(permissions))", server: server, success: true)
    }

    // MARK: - Batch Operations

    func deleteFiles(_ paths: [String], server: Server, credentials: ServerCredentials) async throws {
        for path in paths {
            try await deleteFile(remotePath: path, server: server, credentials: credentials)
        }
    }

    func downloadFiles(_ remotePaths: [String], toDirectory localDir: String, server: Server, credentials: ServerCredentials) async throws {
        for remotePath in remotePaths {
            let fileName = (remotePath as NSString).lastPathComponent
            let localPath = (localDir as NSString).appendingPathComponent(fileName)
            try await downloadFile(remotePath: remotePath, localPath: localPath, server: server, credentials: credentials)
        }
    }

    // MARK: - Helpers

    private func normalized(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "." }
        return trimmed
    }

    private static func shellQuoted(_ raw: String) -> String {
        "'" + raw.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func parseLSLA(_ output: String) -> [SFTPDirectoryEntry] {
        output
            .split(separator: "\n")
            .compactMap { line in
                let stringLine = String(line)
                guard !stringLine.hasPrefix("total ") else { return nil }
                let components = stringLine.split(separator: " ", omittingEmptySubsequences: true)
                guard components.count >= 9 else { return nil }
                let permissions = String(components[0])
                let owner = String(components[2])
                let group = String(components[3])
                let size = String(components[4])
                let modified = "\(components[5]) \(components[6]) \(components[7])"
                let name = components[8...].joined(separator: " ")
                guard name != "." && name != ".." else { return nil }
                let first = permissions.first
                let kind: SFTPDirectoryEntry.EntryKind = switch first {
                case "d": .directory
                case "-": .file
                case "l": .symlink
                default: .unknown
                }
                return SFTPDirectoryEntry(
                    name: name,
                    permissions: permissions,
                    owner: owner,
                    group: group,
                    size: size,
                    modified: modified,
                    kind: kind
                )
            }
            .sorted { lhs, rhs in
                if lhs.kind == .directory && rhs.kind != .directory { return true }
                if lhs.kind != .directory && rhs.kind == .directory { return false }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
}
