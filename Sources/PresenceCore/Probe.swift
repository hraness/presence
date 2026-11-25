import Foundation

public struct SampleOptions: Equatable, Sendable {
    public var filter: VideoFilterOptions
    /// How long to wait for the microphone and camera flags before reporting null.
    public var deviceTimeoutMs: Int
    /// How long to wait for every other probe before reporting null.
    public var probeTimeoutMs: Int

    public init(filter: VideoFilterOptions = VideoFilterOptions(), deviceTimeoutMs: Int = 1_500, probeTimeoutMs: Int = 1_000) {
        self.filter = filter
        self.deviceTimeoutMs = deviceTimeoutMs
        self.probeTimeoutMs = probeTimeoutMs
    }
}

/// Anything that can produce facts: the live machine or a fixture.
public protocol FactsProbe: AnyObject {
    func sample(_ options: SampleOptions) -> PresenceFacts
}

public struct FixtureError: Error, CustomStringConvertible {
    public var description: String
}

/// A JSON file of facts, reread on every sample so tests can change it while `watch` or `wait` runs.
///
/// Missing keys take idle defaults. The file may also hold `assertions` (raw IOPM records) and
/// `processes` (pid to `{name, ppid, startedAtMs}`); then `video` and `videoIgnored` are computed
/// with the same filters the live probe uses.
public final class FixtureProbe: FactsProbe {
    public let path: String

    public init(path: String) {
        self.path = path
    }

    struct Extras: Decodable {
        var assertions: [RawAssertion]?
        var processes: [String: ProcessInfoRecord]?
    }

    public func load(_ options: SampleOptions) throws -> PresenceFacts {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw FixtureError(description: "cannot read fixture \(path): \(error.localizedDescription)")
        }
        do {
            var facts = try JSONDecoder().decode(PresenceFacts.self, from: data)
            let extras = try JSONDecoder().decode(Extras.self, from: data)
            if let assertions = extras.assertions {
                let table = extras.processes ?? [:]
                let split = filterVideo(assertions, options: options.filter) { table[String($0)] }
                facts.video = split.video
                facts.videoIgnored = split.ignored
            }
            facts.source = .fixture
            facts.elapsedMs = 0
            return facts
        } catch let error as DecodingError {
            throw FixtureError(description: "invalid fixture \(path): \(error)")
        }
    }

    public func sample(_ options: SampleOptions) -> PresenceFacts {
        do {
            return try load(options)
        } catch {
            return PresenceFacts(available: false, unavailableReason: "\(error)", source: .fixture)
        }
    }
}
