import SwiftUI

struct ProUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.green)
                Text("All Features Unlocked")
                    .font(.title3.weight(.semibold))
                Text("Store purchases were removed from this build. Pro limits are disabled and all features are available.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .navigationTitle("VVTerm Pro")
        }
    }
}

#Preview {
    ProUpgradeSheet()
}
