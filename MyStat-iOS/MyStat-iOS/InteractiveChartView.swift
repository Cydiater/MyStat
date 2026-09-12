import SwiftUI
import Charts

enum HistoryMetric: String, CaseIterable, Identifiable {
    case cpu = "CPU", memory = "Memory", download = "Download", upload = "Upload", power = "Power"
    var id: Self { self }
    var color: Color {
        switch self {
        case .cpu: return .orange
        case .memory: return .teal
        case .download: return .blue
        case .upload: return .purple
        case .power: return .green
        }
    }
    var title: String { self == .power ? "Battery flow · + in / − out" : rawValue }
    func value(_ sample: StatsSample) -> Double? {
        switch self {
        case .cpu: return sample.cpu
        case .memory: return sample.mem
        case .download: return sample.network?.downloadBytesPerSecond
        case .upload: return sample.network?.uploadBytesPerSecond
        case .power: return sample.power?.batteryWatts
        }
    }
    func formatted(_ value: Double) -> String {
        switch self {
        case .cpu, .memory: return String(format: "%.1f%%", value)
        case .download, .upload: return MetricFormat.rate(value)
        case .power: return (value < 0 ? "−" : value > 0 ? "+" : "") + MetricFormat.watts(value)
        }
    }
}

struct InteractiveChartView: View {
    let samples: [StatsSample]
    let metric: HistoryMetric
    private var title: String { metric.title }
    private var color: Color { metric.color }

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

    private struct ChartPoint: Identifiable {
        let sample: StatsSample
        let segment: Int
        let value: Double
        var id: Date { sample.timestamp }
    }

    private var displayPoints: [ChartPoint] {
        let end = effectiveEnd
        let start = windowStart
        let filtered = samples.filter { $0.timestamp >= start && $0.timestamp <= end }
        // Mark gaps before downsampling so a disconnected or sleeping Mac
        // doesn't appear to have supplied measurements across the missing time.
        var segment = 0
        var previous: Date?
        let points: [ChartPoint] = filtered.compactMap { sample in
            guard let value = metric.value(sample) else { previous = nil; segment += 1; return nil }
            if let previous, sample.timestamp.timeIntervalSince(previous) > 6 { segment += 1 }
            previous = sample.timestamp
            return ChartPoint(sample: sample, segment: segment, value: value)
        }
        guard points.count > 300 else { return points }
        let step = Double(points.count - 1) / 299
        return (0..<300).map { points[Int((Double($0) * step).rounded())] }
    }

    private var currentValue: Double? {
        displayPoints.last?.value
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
                Text(metric.formatted(val)).lineLimit(1).minimumScaleFactor(0.7)
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

    private var yDomain: ClosedRange<Double> {
        if metric == .cpu || metric == .memory { return 0...100 }
        let values = displayPoints.map(\.value)
        let floor = metric == .power ? min(0, (values.min() ?? 0) * 1.15) : 0
        let ceiling = max(metric == .power ? 1 : 1000, (values.max() ?? 0) * 1.15)
        return floor...ceiling
    }

    private var chart: some View {
        Chart(displayPoints) { point in
            LineMark(
                x: .value("Time", point.sample.timestamp),
                y: .value(title, point.value),
                series: .value("Segment", point.segment)
            )
            .foregroundStyle(color)
            .interpolationMethod(.monotone)

            AreaMark(
                x: .value("Time", point.sample.timestamp),
                y: .value(title, point.value),
                series: .value("Segment", point.segment)
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
        .overlay {
            if displayPoints.isEmpty {
                Text("No readings in this range").font(.caption).foregroundStyle(.secondary)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: windowStart...effectiveEnd)
        .chartYAxis {
            AxisMarks(values: [yDomain.lowerBound, (yDomain.lowerBound + yDomain.upperBound) / 2, yDomain.upperBound]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    Text(metric.formatted(value.as(Double.self) ?? 0))
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
                    let earliest = min(Date.now, first.timestamp.addingTimeInterval(duration))
                    if newEnd < earliest {
                        endTime = earliest
                        isLive = earliest >= Date.now.addingTimeInterval(-1)
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
