import SwiftUI

/// Settings panel accessible via ⌘, for managing the SimpleTex API token.
struct SettingsView: View {

    @State private var token: String = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("SimpleTex API Token")
                        .font(.headline)

                    Text("Used for image-to-LaTeX recognition (⌘⇧V / ⌘⌃V). Get a free token at [simpletex.net](https://simpletex.net).")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    SecureField("Paste your token here", text: $token)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Save") {
                            KeychainHelper.save(token: token)
                            saved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                        }
                        .disabled(token.isEmpty)

                        Button("Clear") {
                            KeychainHelper.delete()
                            token = ""
                            saved = false
                        }

                        if saved {
                            Text("✓ Saved")
                                .foregroundStyle(.green)
                                .transition(.opacity)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 200)
        .onAppear {
            token = KeychainHelper.loadToken() ?? ""
        }
    }
}
