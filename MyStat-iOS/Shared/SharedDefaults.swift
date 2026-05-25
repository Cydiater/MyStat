import Foundation

enum SharedDefaults {
    private static let suiteName = "group.com.cydiater.MyStat"

    static func save(cpu: Double, mem: Double, host: String?) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(cpu, forKey: "cpu")
        defaults.set(mem, forKey: "mem")
        defaults.set(Date().timeIntervalSince1970, forKey: "timestamp")
        if let host { defaults.set(host, forKey: "host") }
    }

    static func load() -> (cpu: Double, mem: Double, host: String?, timestamp: Double) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return (0, 0, nil, 0) }
        return (
            defaults.double(forKey: "cpu"),
            defaults.double(forKey: "mem"),
            defaults.string(forKey: "host"),
            defaults.double(forKey: "timestamp")
        )
    }
}
