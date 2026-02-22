import SwiftUI

struct SettingsView: View {
    @AppStorage("derivedDataPath") var derivedDataPath: String = ""

    var body: some View {
        Form {
            Section("DerivedData Location") {
                TextField(
                    "Default: ~/Library/Developer/Xcode/DerivedData",
                    text: $derivedDataPath
                )
                Text("Leave blank to use the default location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 150)
    }
}
