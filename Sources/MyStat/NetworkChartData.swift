import Foundation

struct NetworkChartData {
    let download: [Double?]
    let upload: [Double?]
    let capacity: Int
    let ceiling: Double

    init(download: [Double?] = [], upload: [Double?] = [], capacity: Int = 90) {
        self.capacity = max(2, capacity)
        func clean(_ values: [Double?]) -> [Double?] {
            values.suffix(max(2, capacity)).map { value in
                guard let value, value.isFinite, value >= 0 else { return nil }
                return value
            }
        }
        self.download = clean(download)
        self.upload = clean(upload)
        let peak = max(1_000, (self.download + self.upload).compactMap { $0 }.max() ?? 0)
        let power = pow(10, floor(log10(peak)))
        let multiplier = [1.0, 2, 5, 10].first { $0 >= peak / power } ?? 10
        let rounded = multiplier * power
        ceiling = rounded.isFinite ? rounded : peak
    }
}
