import Cocoa
import Darwin

/// Local presentation only: icon data and executable paths never enter the
/// stats payload. Resolve the PID again each time so PID reuse cannot poison a cache.
final class ProcessIconProvider {
    private let cache = NSCache<NSURL, NSImage>()
    private let fallback = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)!

    init() { cache.countLimit = 96 }

    func icon(for pid: Int32) -> NSImage {
        guard pid > 0 else { return fallback }
        let application = NSRunningApplication(processIdentifier: pid)
        let location = application?.bundleURL ?? Self.executableURL(for: pid)
        if let location, let bundle = Self.owningApplication(at: location) {
            let key = bundle as NSURL
            if let icon = cache.object(forKey: key) { return icon }
            let icon: NSImage
            if application?.bundleURL?.standardizedFileURL == bundle, let runningIcon = application?.icon {
                icon = runningIcon
            } else {
                icon = NSWorkspace.shared.icon(forFile: bundle.path)
            }
            cache.setObject(icon, forKey: key)
            return icon
        }
        return application?.icon ?? fallback
    }

    /// Helpers can live inside a nested .app or .xpc. Use the outer application's
    /// icon (for example Chrome's icon for a renderer), not its generic helper icon.
    static func owningApplication(at location: URL) -> URL? {
        var current = location.standardizedFileURL
        var application: URL?
        while current.path != "/" {
            if current.pathExtension.lowercased() == "app" { application = current }
            current.deleteLastPathComponent()
        }
        return application
    }

    func icon(forApplication bundle: URL) -> NSImage {
        let key = bundle as NSURL
        if let icon = cache.object(forKey: key) { return icon }
        let icon = NSWorkspace.shared.icon(forFile: bundle.path)
        cache.setObject(icon, forKey: key)
        return icon
    }

    static func executableURL(for pid: Int32) -> URL? {
        // PROC_PIDPATHINFO_MAXSIZE is (4 * MAXPATHLEN), a macro Swift cannot import.
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let count = buffer.withUnsafeMutableBytes {
            proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
        }
        guard count > 0 else { return nil }
        let path = String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path)
    }
}
