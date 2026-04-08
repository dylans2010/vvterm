import SwiftUI

struct ProSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)

                Text("All Features Included")
                    .font(.title3.weight(.semibold))

                Text("StoreKit billing has been removed from this build. Workspace, server, and tab limits are disabled.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}

#Preview {
    ProSettingsView()
}
