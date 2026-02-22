import SwiftUI

@main
struct KGBApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { SettingsView() }
    }
}
