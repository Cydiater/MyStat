import SwiftUI

struct NetworkAppsView: View {
    let snapshot: NetworkTrafficSnapshot?
    var needsCompanionUpdate = false
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let stale = snapshot?.isStale(at: context.date) == true
            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                if let snapshot, stale {
                    Text("STALE · last sampled \(snapshot.sampledAt, style: .relative) ago").font(.caption).foregroundStyle(.orange)
                }
                if let snapshot {
                    if snapshot.apps.isEmpty {
                        Text(stale ? "Waiting for a fresh reading" : "No active app traffic")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.apps) { row in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(row.name).font(compact ? .caption.bold() : .subheadline.bold())
                                .lineLimit(2).truncationMode(.middle)
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 16) { rates(row) }
                                VStack(alignment: .leading, spacing: 4) { rates(row) }
                            }
                            .font(compact ? .caption : .subheadline).monospacedDigit()
                        }
                        .opacity(stale ? 0.55 : 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(row.name), download \(MetricFormat.rate(row.downloadBytesPerSecond)), upload \(MetricFormat.rate(row.uploadBytesPerSecond))\(stale ? ", stale reading" : "")")
                    }
                } else {
                    Text(needsCompanionUpdate ? "Update MyStat on your Mac to see network apps." : "Network app readings unavailable. Waiting for samples…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text("Top five by combined traffic · app helpers combined")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("VPNs and proxies can affect attribution. App rates may differ from Wi-Fi and Ethernet totals.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func rates(_ row: NetworkAppTraffic) -> some View {
        Text("↓ \(MetricFormat.rate(row.downloadBytesPerSecond))").foregroundStyle(.blue).fixedSize()
        Text("↑ \(MetricFormat.rate(row.uploadBytesPerSecond))").foregroundStyle(.purple).fixedSize()
    }
}
