import Foundation

/// Reads only token-count events. Prompts, responses, paths and credentials are
/// neither retained nor included in the stats protocol.
public struct CodexUsageAccumulator {
    private struct Counts: Decodable, Equatable {
        let input_tokens: Int64
        let cached_input_tokens: Int64
        let output_tokens: Int64
        var valid: Bool {
            input_tokens >= 0 && cached_input_tokens >= 0 && cached_input_tokens <= input_tokens && output_tokens >= 0
                && !input_tokens.addingReportingOverflow(output_tokens).overflow
        }
    }
    private struct Event: Decodable {
        struct Payload: Decodable {
            struct Info: Decodable {
                let total_token_usage: Counts?
                let last_token_usage: Counts?
            }
            let type: String
            let info: Info?
        }
        let type: String
        let timestamp: String
        let payload: Payload
    }
    public let dayStart: Date
    private let dayEnd: Date
    private let timeZone: String
    private var previous: [String: Counts] = [:]
    private var seen: Set<String> = []
    private var input: Int64 = 0
    private var cached: Int64 = 0
    private var output: Int64 = 0
    public private(set) var hasUsage = false
    private let fractional = ISO8601DateFormatter()
    private let whole = ISO8601DateFormatter()

    public init(now: Date, calendar: Calendar = .current) {
        dayStart = calendar.startOfDay(for: now)
        dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        timeZone = calendar.timeZone.identifier
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    public mutating func consume(_ line: Data, source: String) {
        guard line.range(of: Data("\"token_count\"".utf8)) != nil,
              let event = try? JSONDecoder().decode(Event.self, from: line),
              event.type == "event_msg", event.payload.type == "token_count",
              let info = event.payload.info, let total = info.total_token_usage, total.valid,
              let date = fractional.date(from: event.timestamp) ?? whole.date(from: event.timestamp) else { return }
        let old = previous[source]
        previous[source] = total
        hasUsage = true
        guard date >= dayStart, date < dayEnd else { return }
        // Repeated notifications (including rate-limit-only updates) carry the
        // same cumulative counts. Copied/forked logs may repeat entire events.
        let fingerprint = "\(event.timestamp)|\(total.input_tokens)|\(total.cached_input_tokens)|\(total.output_tokens)"
        guard seen.insert(fingerprint).inserted, old != total else { return }
        let delta: Counts
        if let old, total.input_tokens >= old.input_tokens,
           total.cached_input_tokens >= old.cached_input_tokens, total.output_tokens >= old.output_tokens {
            delta = Counts(input_tokens: total.input_tokens - old.input_tokens,
                           cached_input_tokens: total.cached_input_tokens - old.cached_input_tokens,
                           output_tokens: total.output_tokens - old.output_tokens)
        } else if let last = info.last_token_usage, last.valid {
            // A first event can inherit prior context. Only its last request is
            // attributable here; never import an unknown lifetime total.
            delta = last
        } else { return }
        guard delta.valid,
              !input.addingReportingOverflow(delta.input_tokens).overflow,
              !cached.addingReportingOverflow(delta.cached_input_tokens).overflow,
              !output.addingReportingOverflow(delta.output_tokens).overflow else { return }
        let nextInput = input + delta.input_tokens
        let nextOutput = output + delta.output_tokens
        guard !nextInput.addingReportingOverflow(nextOutput).overflow else { return }
        input = nextInput
        cached += delta.cached_input_tokens
        output = nextOutput
    }

    public mutating func resetSource(_ source: String) {
        previous.removeValue(forKey: source)
    }

    public func snapshot(at date: Date) -> TokenUsage {
        TokenUsage(inputTokens: input, cachedInputTokens: cached, outputTokens: output,
                   updatedAt: date, dayStart: dayStart, timeZone: timeZone)
    }
}

/// Bounded JSONL framing tolerates partial appends and skips huge non-usage
/// records without retaining conversation-sized buffers.
public struct UsageLineBuffer {
    private var pending = Data()
    private var discarding = false
    public static let maximumLineSize = 256 * 1024
    public init() {}

    public mutating func append(_ data: Data, onLine: (Data) -> Void) {
        var start = data.startIndex
        while start < data.endIndex {
            let newline = data[start...].firstIndex(of: 10)
            let end = newline ?? data.endIndex
            if !discarding {
                if pending.count + end - start > Self.maximumLineSize {
                    pending.removeAll(keepingCapacity: true)
                    discarding = true
                } else { pending.append(data[start..<end]) }
            }
            guard let newline else { break }
            if !discarding { onLine(pending) }
            pending.removeAll(keepingCapacity: true)
            discarding = false
            start = newline + 1
        }
    }
}
