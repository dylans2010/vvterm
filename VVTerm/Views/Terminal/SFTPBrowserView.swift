import SwiftUI

struct SFTPBrowserView: View {
    let sessionId: UUID
    let server: Server
    let credentials: ServerCredentials

    @StateObject private var manager = SFTPConnectionManager.shared

    private var entries: [SFTPDirectoryEntry] {
        manager.entriesByServer[server.id] ?? []
    }

    private var currentPath: String {
        manager.currentPathByServer[server.id] ?? "."
    }

    private var isLoading: Bool {
        manager.isLoadingByServer[server.id] ?? false
    }

    private var error: String? {
        manager.lastErrorByServer[server.id]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let error {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await manager.refreshListing(for: server, credentials: credentials) }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty && isLoading {
                ProgressView("Loading SFTP directory…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    Button {
                        if entry.kind == .directory {
                            Task { await manager.navigateInto(entry, for: server, credentials: credentials) }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: icon(for: entry.kind))
                                .foregroundStyle(entry.kind == .directory ? .tint : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .font(.body)
                                    .lineLimit(1)
                                Text("\(entry.permissions) · \(entry.owner):\(entry.group) · \(entry.size)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(entry.modified)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .task(id: server.id) {
            ConnectionSessionManager.shared.updateSessionState(sessionId, to: .connected)
            if manager.entriesByServer[server.id] == nil {
                await manager.refreshListing(for: server, credentials: credentials)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("SFTP")
                .font(.headline)
            Text(currentPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                Task { await manager.navigateUp(for: server, credentials: credentials) }
            } label: {
                Label("Up", systemImage: "arrow.up")
            }
            .buttonStyle(.bordered)

            Button {
                Task { await manager.refreshListing(for: server, credentials: credentials) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func icon(for kind: SFTPDirectoryEntry.EntryKind) -> String {
        switch kind {
        case .directory: return "folder"
        case .file: return "doc.text"
        case .symlink: return "arrowshape.turn.up.right"
        case .unknown: return "questionmark.square.dashed"
        }
    }
}
