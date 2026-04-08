import Foundation
import os.log
import Combine

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
}

@MainActor
final class SFTPConnectionManager: ObservableObject {
    static let shared = SFTPConnectionManager()

    @Published private(set) var entriesByServer: [UUID: [SFTPDirectoryEntry]] = [:]
    @Published private(set) var currentPathByServer: [UUID: String] = [:]
    @Published private(set) var lastErrorByServer: [UUID: String] = [:]
    @Published private(set) var isLoadingByServer: [UUID: Bool] = [:]

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.vivy.VivyTerm", category: "SFTP")

    private init() {}

    func refreshListing(for server: Server, credentials: ServerCredentials, path: String? = nil) async {
        isLoadingByServer[server.id] = true
        defer { isLoadingByServer[server.id] = false }

        let targetPath = normalized(path ?? currentPathByServer[server.id] ?? ".")
        logger.info("Refreshing SFTP listing for server=\(server.name, privacy: .public) path=\(targetPath, privacy: .private)")

        do {
            let snapshot = try await SSHConnectionOperationService.shared.withTemporaryConnection(server: server, credentials: credentials) { client in
                let pwd = try await client.execute("pwd")
                let resolvedPath = path ?? pwd.trimmingCharacters(in: .whitespacesAndNewlines)
                let escapedPath = Self.shellQuoted(normalized(resolvedPath.isEmpty ? "." : resolvedPath))
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
