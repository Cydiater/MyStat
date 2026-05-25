import SwiftUI

struct ContentView: View {
    @State private var client = StatsClient()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if client.isConnected {
                ScrollView {
                    VStack(spacing: 24) {
                        header

                        HStack(spacing: 48) {
                            GaugeView(title: "CPU", value: client.cpu, color: .orange)
                            GaugeView(title: "MEM", value: client.mem, color: .teal)
                        }

                        VStack(spacing: 20) {
                            InteractiveChartView(
                                samples: client.store.samples,
                                title: "CPU",
                                color: .orange,
                                valuePath: \.cpu
                            )

                            InteractiveChartView(
                                samples: client.store.samples,
                                title: "Memory",
                                color: .teal,
                                valuePath: \.mem
                            )
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding()
                }
                .scrollIndicators(.hidden)
            } else {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)

                    Text("Looking for MyStat\non your network\u{2026}")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("Make sure MyStat is running on your Mac\nand both devices are on the same Wi-Fi.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .onAppear { client.start() }
        .onDisappear { client.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                client.store.saveNow()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "desktopcomputer")
            Text(client.hostName ?? "Mac")
        }
        .font(.headline)
        .foregroundStyle(.secondary)
    }
}
