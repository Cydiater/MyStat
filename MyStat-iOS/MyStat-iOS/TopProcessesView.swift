import SwiftUI

struct TopProcessesView: View {
    let snapshot: ProcessSnapshot?
    var sideBySide = false
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let layout = sideBySide ? AnyLayout(HStackLayout(alignment: .top, spacing: 12)) : AnyLayout(VStackLayout(spacing: 12))
            layout {
                processList(cpu: true, now: context.date)
                processList(cpu: false, now: context.date)
            }
        }
    }

    private func processList(cpu: Bool, now: Date) -> some View {
        let rows = cpu ? snapshot?.topCPU ?? [] : snapshot?.topMemory ?? []
        let color: Color = cpu ? .orange : .teal
        let stale = snapshot?.isStale(at: now) == true
        return VStack(alignment: .leading, spacing: compact ? 6 : 12) {
            HStack {
                Text(cpu ? "Top CPU processes" : "Top memory processes")
                    .font(compact ? .caption.bold() : .subheadline.bold()).foregroundStyle(color)
                Spacer(minLength: 0)
                if stale { Text("STALE").font(.caption2.bold()).foregroundStyle(.orange) }
            }
            if rows.isEmpty {
                Text(snapshot == nil ? "Process readings unavailable" : cpu ? "Measuring CPU…" : "No readable processes")
                    .font(.subheadline).foregroundStyle(.secondary)
                if snapshot == nil && !compact {
                    Text("Use the latest Mac companion to see its busiest processes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.name).font(compact ? .caption : .subheadline).lineLimit(1).truncationMode(.middle)
                            Text("PID \(row.pid)").font(.system(size: compact ? 9 : 10, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Text(cpu ? row.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—" : MetricFormat.bytes(row.residentBytes))
                            .font(compact ? .caption.bold() : .subheadline.bold()).monospacedDigit().foregroundStyle(color)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .opacity(stale ? 0.55 : 1)
                    .accessibilityElement(children: .combine)
                }
            }
            Text(cpu ? "100% = one core · readable processes" : "Resident memory · shared pages may overlap")
                .font(.system(size: compact ? 9 : 11)).foregroundStyle(.secondary)
            if let snapshot, stale {
                Text("Last sampled \(snapshot.sampledAt, style: .relative) ago").font(.caption2).foregroundStyle(.orange)
            }
        }
        .padding(compact ? 12 : 18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.13)))
    }
}
