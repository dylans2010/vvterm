import SwiftUI

struct TranscriptionSettingsView: View {
    var body: some View {
        Form {
            Section {
                Label("Apple Speech", systemImage: "waveform")
                Text("On-device speech transcription uses Apple Speech only in this build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    TranscriptionSettingsView()
}
