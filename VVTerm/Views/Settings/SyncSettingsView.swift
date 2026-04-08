import SwiftUI

struct SyncSettingsView: View {
    var body: some View {
        Form {
            Section {
                Label("Local-Only Mode", systemImage: "internaldrive")
                Text("Cloud sync has been removed. All servers and workspaces are stored on this device only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    SyncSettingsView()
}
