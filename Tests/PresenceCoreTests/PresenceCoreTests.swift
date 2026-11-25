import Foundation
import Testing
@testable import PresenceCore

private func fixture(_ name: String) -> String {
    Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!.path
}

private func load(_ name: String, _ options: SampleOptions = SampleOptions()) throws -> PresenceFacts {
    try FixtureProbe(path: fixture(name)).load(options)
}

private func sampled(_ name: String, _ options: SampleOptions = SampleOptions(), keyIdleMinutes: Double = 5) throws -> Presence {
    classify(try load(name, options), keyIdleMinutes: keyIdleMinutes)
}

private func state(_ facts: PresenceFacts) -> PresenceState? {
    classify(facts, keyIdleMinutes: 5).state
}

private func reason(_ facts: PresenceFacts) -> String {
    classify(facts, keyIdleMinutes: 5).reason
}

@Suite struct ClassifyTests {
    @Test func idleAfterThreshold() throws {
        let presence = try sampled("idle")
        #expect(presence.state == .idle)
        #expect(presence.busy == false)
        #expect(presence.reason == "owner idle 15m, no video or call")
    }

    @Test func typingWithinThreshold() throws {
        let presence = try sampled("typing")
        #expect(presence.state == .typing)
        #expect(presence.busy == true)
        #expect(presence.reason == "typed 12s ago")
        #expect(try sampled("typing", keyIdleMinutes: 0.1).state == .idle)
    }

    @Test func lockBeatsEverything() throws {
        let presence = try sampled("locked")
        #expect(presence.state == .away)
        #expect(presence.busy == false)
        #expect(presence.reason == "screen locked")
    }

    @Test func displays() {
        #expect(reason(PresenceFacts(displaysOnline: 0, displaysAwake: 0)) == "lid closed with no display")
        #expect(reason(PresenceFacts(displaysOnline: 2, displaysAwake: 0)) == "display asleep")
        #expect(state(PresenceFacts(displaysOnline: 2, displaysAwake: 1)) == .idle)
    }

    @Test func callSignals() {
        #expect(reason(PresenceFacts(camera: true)) == "camera in use")
        #expect(reason(PresenceFacts(microphone: true)) == "microphone in use")
        #expect(reason(PresenceFacts(screenSharing: true)) == "screen sharing")
        #expect(state(PresenceFacts(screenSharing: nil)) == .call)
    }

    @Test func unknownDevicesCountAsCall() throws {
        let presence = try sampled("devices-unknown")
        #expect(presence.facts.microphone == nil)
        #expect(presence.state == .call)
        #expect(presence.reason == "microphone or camera state unknown")
        #expect(state(PresenceFacts(camera: nil)) == .call)
    }

    @Test func video() {
        let playing = VideoAssertion(pid: 9, process: "IINA", assertionName: "playback", since: 1)
        #expect(reason(PresenceFacts(video: [playing])) == "video playing in IINA")
        #expect(reason(PresenceFacts(video: nil)) == "video state unknown")
    }

    @Test func unknownIdleCountsAsTyping() {
        #expect(state(PresenceFacts(keyIdleSeconds: nil)) == .typing)
    }

    @Test func unavailable() throws {
        let presence = try sampled("unavailable")
        #expect(!presence.available)
        #expect(presence.state == nil)
        #expect(presence.busy == nil)
        #expect(presence.reason == "no GUI session")
        #expect(humanLine(presence) == "unavailable: no GUI session")
    }

    @Test func durations() {
        #expect(durationText(-3) == "0s")
        #expect(durationText(59.9) == "59s")
        #expect(durationText(60) == "1m")
        #expect(durationText(3_600 + 5 * 60) == "1h05m")
    }
}

@Suite struct VideoFilterTests {
    @Test func builtInFilters() throws {
        let facts = try load("assertions")
        #expect(facts.video?.map(\.process) == ["Google Chrome Helper", "Simulator"])
        #expect(facts.video?.first?.since == 2000)
        #expect(facts.videoIgnored.map(\.ignoredBecause) == [.keepAwake, .agent])
        // System-sleep assertions are not display assertions and are dropped entirely.
        #expect(!facts.videoIgnored.contains { $0.process == "powerd" })
        #expect(reason(facts) == "video playing in Google Chrome Helper")
    }

    @Test func ignoreTree() throws {
        let facts = try load("assertions", SampleOptions(filter: VideoFilterOptions(ignoreTrees: [790])))
        #expect(facts.video?.map(\.pid) == [500])
        #expect(facts.videoIgnored.first { $0.pid == 800 }?.ignoredBecause == .ignoredTree)
        // The pid itself counts as part of its tree.
        let own = try load("assertions", SampleOptions(filter: VideoFilterOptions(ignoreTrees: [500])))
        #expect(own.videoIgnored.first { $0.pid == 500 }?.ignoredBecause == .ignoredTree)
    }

    @Test func since() throws {
        let facts = try load("assertions", SampleOptions(filter: VideoFilterOptions(since: 4000)))
        #expect(facts.video?.map(\.pid) == [500])
        #expect(facts.videoIgnored.first { $0.pid == 800 }?.ignoredBecause == .since)
    }

    @Test func startedAfter() throws {
        let facts = try load("assertions", SampleOptions(filter: VideoFilterOptions(ignorePidsStartedAfter: 1500)))
        #expect(facts.video == [])
        #expect(facts.videoIgnored.filter { $0.ignoredBecause == .startedAfter }.map(\.pid) == [500, 700, 800])
        // Keep-awake wins over every other reason.
        #expect(facts.videoIgnored.first { $0.pid == 1908 }?.ignoredBecause == .keepAwake)
    }

    @Test func ignoreProcessExtendsAgents() throws {
        let facts = try load("assertions", SampleOptions(filter: VideoFilterOptions(ignoreProcesses: ["xctest-runner"])))
        #expect(facts.video?.map(\.pid) == [500])
        #expect(facts.videoIgnored.first { $0.pid == 800 }?.ignoredBecause == .agent)
    }

    @Test func defaultAgentsAreGeneric() {
        #expect(agentProcesses == ["claude", "codex", "cursor-agent", "xcodebuild"])
        let raw = [RawAssertion(pid: 20, process: "Safari", assertionName: "v", type: "PreventUserIdleDisplaySleep", since: nil)]
        let table: [Int32: ProcessInfoRecord] = [
            20: ProcessInfoRecord(name: "Safari", ppid: 10, startedAtMs: 0),
            10: ProcessInfoRecord(name: "host-run", ppid: 1, startedAtMs: 0),
        ]
        #expect(filterVideo(raw) { table[$0] }.video.map(\.pid) == [20])
        #expect(filterVideo(raw, options: VideoFilterOptions(ignoreProcesses: ["host-run"])) { table[$0] }.ignored.map(\.ignoredBecause) == [.agent])
    }

    @Test func unknownOwnerFallsBackToIOPMName() {
        let raw = [RawAssertion(pid: 42, process: "caffeinate", assertionName: "x", type: "PreventUserIdleDisplaySleep", since: nil)]
        #expect(filterVideo(raw) { _ in nil }.ignored.map(\.ignoredBecause) == [.keepAwake])
        let legacy = [RawAssertion(pid: 43, process: nil, assertionName: "y", type: "Legacy", trueType: "PreventUserIdleDisplaySleep", since: nil)]
        #expect(filterVideo(legacy) { _ in nil }.video.map(\.process) == ["pid 43"])
    }
}

@Suite struct OutputTests {
    @Test func jsonSchema() throws {
        let line = jsonLine(try sampled("devices-unknown"), sampledAt: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(!line.contains("\n"))
        let object = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        #expect(Set(object.keys) == ["schemaVersion", "available", "state", "busy", "reason", "sampledAt", "facts"])
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["sampledAt"] as? Int == 1_700_000_000_000)
        #expect(object["state"] as? String == "call")
        let facts = try #require(object["facts"] as? [String: Any])
        #expect(Set(facts.keys) == [
            "available", "unavailableReason", "keyIdleSeconds", "inputIdleSeconds", "locked", "displaysOnline",
            "displaysAwake", "video", "videoIgnored", "microphone", "camera", "screenSharing", "source", "elapsedMs",
        ])
        // Unknown is an explicit null, never a missing key.
        #expect(facts["microphone"] is NSNull)
        #expect(facts["source"] as? String == "fixture")
    }

    @Test func unavailableJSON() throws {
        let object = try #require(JSONSerialization.jsonObject(with: Data(jsonLine(try sampled("unavailable")).utf8)) as? [String: Any])
        #expect(object["available"] as? Bool == false)
        #expect(object["state"] is NSNull)
        #expect(object["busy"] is NSNull)
    }

    @Test func factsRoundTrip() throws {
        let facts = PresenceFacts(
            keyIdleSeconds: 1.2345,
            video: [VideoAssertion(pid: 1, process: "p", assertionName: "a", since: nil)],
            microphone: nil,
            source: .system,
            elapsedMs: 4.5
        )
        let decoded = try JSONDecoder().decode(PresenceFacts.self, from: JSONEncoder().encode(facts))
        #expect(decoded.keyIdleSeconds == 1.235)
        #expect(decoded.microphone == nil)
        #expect(decoded.video == facts.video)
        #expect(decoded.source == .system)
    }

    @Test func badFixture() throws {
        let path = NSTemporaryDirectory() + "presence-bad-\(UUID().uuidString).json"
        try Data("{\"locked\": \"yes\"}".utf8).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(throws: FixtureError.self) { try FixtureProbe(path: path).load(SampleOptions()) }
        #expect(!FixtureProbe(path: path).sample(SampleOptions()).available)
        #expect(throws: FixtureError.self) { try FixtureProbe(path: path + ".missing").load(SampleOptions()) }
    }
}

@Suite struct OptionsTests {
    @Test func defaults() throws {
        let options = try parseOptions([])
        #expect(options.command == .sample)
        #expect(!options.json)
        #expect(options.keyIdleMinutes == 5)
        #expect(options.intervalSeconds == 2)
        #expect(options.sample.deviceTimeoutMs == 1_500)
    }

    @Test func flags() throws {
        let options = try parseOptions([
            "--json", "--key-idle-minutes", "2.5", "--ignore-pids-started-after=1700000000000",
            "--since", "1700000000001", "--ignore-tree", "12", "--ignore-tree", "13", "--device-timeout-ms", "250",
            "--ignore-process", "host-run", "--ignore-process=ohd",
        ])
        #expect(options.json)
        #expect(options.keyIdleMinutes == 2.5)
        #expect(options.sample.filter == VideoFilterOptions(
            ignorePidsStartedAfter: 1_700_000_000_000, since: 1_700_000_000_001, ignoreTrees: [12, 13], ignoreProcesses: ["host-run", "ohd"]
        ))
        #expect(options.sample.deviceTimeoutMs == 250)
    }

    @Test func commands() throws {
        #expect(try parseOptions(["watch", "--json", "--every-sample"]).command == .watch(everySample: true))
        #expect(try parseOptions(["wait", "--until", "away", "--timeout", "1h30m"]).command == .wait(until: .away, idleMinutes: 0, timeoutSeconds: 5_400))
        #expect(try parseOptions(["wait", "--until", "idle", "--idle-minutes", "3"]).command == .wait(until: .idle, idleMinutes: 3, timeoutSeconds: nil))
        #expect(try parseOptions(["--help"]).command == .help)
        #expect(try parseOptions(["--version"]).command == .version)
    }

    @Test(arguments: [
        ["bogus"], ["--nope"], ["wait"], ["wait", "--until", "sleepy"], ["--until", "idle"], ["watch", "--timeout", "5"],
        ["wait", "--until", "idle", "--every-sample"], ["--key-idle-minutes"], ["--key-idle-minutes", "-1"],
        ["--json", "--json"], ["--ignore-tree", "0"], ["--device-timeout-ms", "0"], ["wait", "--until", "idle", "--timeout", "5x"],
        ["--interval", "0.01"], ["--ignore-process"], ["--ignore-process", ""],
    ])
    func usageErrors(_ arguments: [String]) {
        #expect(throws: UsageError.self) { try parseOptions(arguments) }
    }

    @Test func durations() {
        #expect(parseDuration("90") == 90)
        #expect(parseDuration("90s") == 90)
        #expect(parseDuration("500ms") == 0.5)
        #expect(parseDuration("5m") == 300)
        #expect(parseDuration("1h30m") == 5_400)
        #expect(parseDuration("1.5h") == 5_400)
        #expect(parseDuration("") == nil)
        #expect(parseDuration("m") == nil)
        #expect(parseDuration("5x") == nil)
        #expect(parseDuration("5m3") == nil)
    }
}

/// A fake clock: sleeping advances time instantly.
private final class FakeClock {
    var time = 0.0
    var sleeps: [Double] = []
}

/// Replays samples in order, repeating the last one.
private func environment(_ samples: [Presence], clock: FakeClock, emitted: @escaping (Presence) -> Void = { _ in }) -> LoopEnvironment {
    var queue = samples[...]
    return LoopEnvironment(
        sample: { queue.count > 1 ? queue.popFirst()! : queue.first! },
        now: { clock.time },
        sleep: { clock.sleeps.append($0); clock.time += $0 },
        emit: emitted
    )
}

@Suite struct LoopTests {
    let idle = classify(PresenceFacts(), keyIdleMinutes: 5)
    let typing = classify(PresenceFacts(keyIdleSeconds: 3, inputIdleSeconds: 1), keyIdleMinutes: 5)
    let away = classify(PresenceFacts(locked: true), keyIdleMinutes: 5)
    let unavailable = classify(PresenceFacts(available: false, unavailableReason: "no session"), keyIdleMinutes: 5)

    @Test func watchPrintsChangesOnly() {
        let clock = FakeClock()
        var out: [PresenceState?] = []
        watch(everySample: false, interval: 2, environment: environment([typing, typing, idle, idle, typing], clock: clock) { out.append($0.state) }, maxSamples: 5)
        #expect(out == [.typing, .idle, .typing])
        #expect(clock.sleeps == [2, 2, 2, 2])
    }

    @Test func watchEverySample() {
        var count = 0
        watch(everySample: true, interval: 2, environment: environment([typing], clock: FakeClock()) { _ in count += 1 }, maxSamples: 3)
        #expect(count == 3)
    }

    @Test func waitReachesIdle() {
        let clock = FakeClock()
        var last: Presence?
        let code = wait(until: .idle, idleMinutes: 0, timeout: nil, interval: 2, environment: environment([typing, typing, idle], clock: clock) { last = $0 })
        #expect(code == .ok)
        #expect(last?.state == .idle)
        #expect(clock.time == 4)
    }

    @Test func waitIdleAcceptsAway() {
        #expect(wait(until: .idle, idleMinutes: 10, timeout: nil, interval: 2, environment: environment([away], clock: FakeClock())) == .ok)
        #expect(wait(until: .away, idleMinutes: 0, timeout: 5, interval: 2, environment: environment([idle], clock: FakeClock())) == .timeout)
    }

    @Test func waitTimesOut() {
        let clock = FakeClock()
        #expect(wait(until: .idle, idleMinutes: 0, timeout: 5, interval: 2, environment: environment([typing], clock: clock)) == .timeout)
        #expect(clock.time == 5)
        #expect(ExitCode.timeout.rawValue == 124)
    }

    @Test func idleMinutesNeedsNoInput() {
        let reading = classify(PresenceFacts(keyIdleSeconds: 900, inputIdleSeconds: 30), keyIdleMinutes: 5)
        #expect(reading.state == .idle)
        #expect(!reached(reading, until: .idle, idleMinutes: 1))
        #expect(reached(reading, until: .idle, idleMinutes: 0.5))
    }

    @Test func waitStopsWhenUnavailable() {
        #expect(wait(until: .idle, idleMinutes: 0, timeout: nil, interval: 2, environment: environment([unavailable], clock: FakeClock())) == .unavailable)
    }
}
