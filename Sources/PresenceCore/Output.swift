import Foundation

/// Version of the JSON object printed by `--json`. Bump it on any breaking change.
public let schemaVersion = 1

struct Report: Encodable {
    var presence: Presence
    var sampledAt: Date

    enum Keys: String, CodingKey {
        case schemaVersion, available, state, busy, reason, sampledAt, facts
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(presence.available, forKey: .available)
        try c.encode(presence.state, forKey: .state)
        try c.encode(presence.busy, forKey: .busy)
        try c.encode(presence.reason, forKey: .reason)
        try c.encode(Int64((sampledAt.timeIntervalSince1970 * 1_000).rounded()), forKey: .sampledAt)
        try c.encode(presence.facts, forKey: .facts)
    }
}

/// One line of JSON with sorted keys, so the output is byte-stable for equal input.
public func jsonLine(_ presence: Presence, sampledAt: Date = Date()) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    // Encoding plain values cannot fail.
    let data = (try? encoder.encode(Report(presence: presence, sampledAt: sampledAt))) ?? Data("{}".utf8)
    return String(decoding: data, as: UTF8.self)
}

/// `typing: typed 4s ago`, `unavailable: no GUI session`.
public func humanLine(_ presence: Presence) -> String {
    guard let state = presence.state else { return "unavailable: \(presence.reason)" }
    return "\(state.rawValue): \(presence.reason)"
}
