import SwiftUI

struct PopoverView: View {
    let store: CommandStore

    var body: some View {
        VStack {
            Text("KGB — Known Good Build")
                .font(.headline)
            Text("No commands yet")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 420, height: 300)
    }
}
