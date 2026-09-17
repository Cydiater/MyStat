import SwiftUI

struct SetupHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Connect your Mac") {
                    Text("1. Download and open the free MyStat companion on your Mac. Requires macOS 12 or later.")
                    Link("Get the Free Mac App", destination: URL(string: "https://cydiater.github.io/MyStat/")!)
                    Text("2. Connect your iPhone and Mac to the same trusted local network.")
                    Text("3. Allow Local Network access on your iPhone. MyStat finds your Mac automatically; use the computer menu to choose one.")
                }
                Section("Live readings and widgets") {
                    Text("Keep Desk Display open for live readings. Turn on Keep Awake in the Mac menu if monitoring should continue while its display sleeps.")
                    Text("Widgets show snapshots. iOS chooses refresh timing; tap Refresh for a new reading.")
                }
                Section("Update the Mac companion") {
                    Text("In the Mac menu, choose Check for Updates… to see release notes and install an update. You can also enable Automatically Check for Updates; installing still requires your choice.")
                    Text("If your Mac app has no update menu, download the latest companion once. Existing connections and history stay on your devices.")
                    Link("Mac download & release notes", destination: URL(string: "https://github.com/Cydiater/MyStat/releases/latest")!)
                }
                Section("About the readings") {
                    Text("Battery watts show net charging or discharging where supported, not wall power or total Mac consumption. Adapter watts are its reported rating.")
                    Text("Codex tokens come from local session logs. They are estimates of recorded usage, not account quota or billing. MyStat is independent and is not affiliated with OpenAI.")
                }
                Section("Help and privacy") {
                    Link("Setup & Support", destination: URL(string: "https://cydiater.github.io/MyStat/support.html")!)
                    Link("Privacy Policy", destination: URL(string: "https://cydiater.github.io/MyStat/privacy.html")!)
                    Text("No account, advertising, tracking, or cloud service. Stats stay on your devices and local network. The Mac shares read-only stats over unencrypted local HTTP, so use a trusted network.")
                }
            }
            .navigationTitle("Set Up MyStat")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
