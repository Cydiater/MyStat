import SwiftUI
import Charts

struct InteractiveChartView: View {
    let samples: [StatsSample]
    let title: String
    let color: Color
    let valuePath: KeyPath<StatsSample, Double>

    @State private var duration: TimeInterval = 300
    @State private var endTime: Date = .now
    @State private var isLive = true
    @State private var chartWidth: CGFloat = 300

    @GestureState private var pinchScale: CGFloat = 1.0
    @GestureState private var dragOffset: CGFloat = 0

    private var effectiveDuration: TimeInterval {
        let d = duration / Double(pinchScale)
        return max(10, min(d, maxDuration))
    }

    private var effectiveEnd: Date {
        if isLive && dragOffset == 0 { return .now }
        let spp = effectiveDuration / Double(chartWidth)
        let ref = isLive ? Date.now : endTime
        return ref.addingTimeInterval(-Double(dragOffset) * spp)
    }

    private var maxDuration: TimeInterval {
        guard let first = samples.first else { return 300 }
        return max(300, Date.now.timeIntervalSince(first.timestamp))
    }

    private var windowStart: Date {
        effectiveEnd.addingTimeInterval(-effectiveDuration)
    }

    private var displaySamples: [StatsSample] {
        let end = effectiveEnd
        let start = windowStart
        let filtered = samples.filter { $0.timestamp >= start && $0.timestamp <= end }
        return downsample(filtered, maxPoints: 300)
    }

    private var currentValue: Double? {
        displaySamples.last?[keyPath: valuePath]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            chart
                .frame(height: 170)
                .contentShape(Rectangle())
                .gesture(pinchGesture)
                .simultaneousGesture(panGesture)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { chartWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, w in chartWidth = w }
                    }
                )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)

            if let val = currentValue {
                Text(String(format: "%.1f%%", val))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            Text(durationLabel(effectiveDuration))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            if !isLive {
                Button {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isLive = true
                        endTime = .now
                    }
                } label: {
                    Text("Live")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var chart: some View {
        Chart(displaySamples, id: \.timestamp) { sample in
            LineMark(
                x: .value("Time", sample.timestamp),
                y: .value(title, sample[keyPath: valuePath])
            )
            .foregroundStyle(color)
            .interpolationMethod(.monotone)

            AreaMark(
                x: .value("Time", sample.timestamp),
                y: .value(title, sample[keyPath: valuePath])
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [color.opacity(0.2), color.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: windowStart...effectiveEnd)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    Text("\(value.as(Int.self) ?? 0)")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .chartXAxis {
            AxisMarks(preset: .automatic, values: .automatic) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(timeLabel(date))
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(.white.opacity(0.03))
                .border(.white.opacity(0.06))
        }
    }

    // MARK: - Gestures

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                let newDuration = duration / Double(value)
                duration = max(10, min(newDuration, maxDuration))
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragOffset) { value, state, _ in
                state = value.translation.width
            }
            .onEnded { value in
                let spp = effectiveDuration / Double(chartWidth)
                let offset = Double(value.translation.width) * spp
                let newEnd = (isLive ? Date.now : endTime).addingTimeInterval(-offset)

                isLive = false

                if let first = samples.first {
                    let earliest = first.timestamp.addingTimeInterval(duration)
                    if newEnd < earliest {
                        endTime = earliest
                        return
                    }
                }
                if newEnd >= .now {
                    endTime = .now
                    isLive = true
                    return
                }
                endTime = newEnd
            }
    }

    // MARK: - Helpers

    private func downsample(_ data: [StatsSample], maxPoints: Int) -> [StatsSample] {
        guard data.count > maxPoints else { return data }
        let step = Double(data.count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { i in
            data[Int(Double(i) * step)]
        }
    }

    private func durationLabel(_ d: TimeInterval) -> String {
        if d < 60 { return "\(Int(d))s" }
        if d < 3600 { return "\(Int(d / 60))m" }
        if d < 86400 { return String(format: "%.1fh", d / 3600) }
        return String(format: "%.1fd", d / 86400)
    }

    private func timeLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        if effectiveDuration < 600 {
            fmt.dateFormat = "HH:mm:ss"
        } else if effectiveDuration < 86400 {
            fmt.dateFormat = "HH:mm"
        } else {
            fmt.dateFormat = "M/d HH:mm"
        }
        return fmt.string(from: date)
    }
}
