import Foundation

/// A display-sleep assertion that counts as video playback.
public struct VideoAssertion: Codable, Equatable, Sendable {
    public var pid: Int32
    /// Name of the owning process.
    public var process: String
    /// The assertion's own name, as the app set it.
    public var assertionName: String
    /// When the assertion was created, in ms since the Unix epoch (IOPM `AssertStartWhen`), or null.
    public var since: Int64?

    public init(pid: Int32, process: String, assertionName: String, since: Int64?) {
        self.pid = pid
        self.process = process
        self.assertionName = assertionName
        self.since = since
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pid, forKey: .pid)
        try c.encode(process, forKey: .process)
        try c.encode(assertionName, forKey: .assertionName)
        try c.encode(since, forKey: .since)
    }
}

/// Why a display-sleep assertion was not counted as video.
public enum IgnoreReason: String, Codable, Sendable, CaseIterable {
    /// The owner is a keep-awake utility (Amphetamine, caffeinate, ...).
    case keepAwake = "keep-awake"
    /// The owner is, or descends from, an agent or build process.
    case agent
    /// The owner is, or descends from, a pid passed with `--ignore-tree`.
    case ignoredTree = "ignored-tree"
    /// The assertion was created at or after `--since`.
    case since
    /// The owner started at or after `--ignore-pids-started-after`.
    case startedAfter = "started-after"
}

public struct IgnoredAssertion: Codable, Equatable, Sendable {
    public var pid: Int32
    public var process: String
    public var assertionName: String
    public var since: Int64?
    public var ignoredBecause: IgnoreReason

    public init(_ assertion: VideoAssertion, because reason: IgnoreReason) {
        pid = assertion.pid
        process = assertion.process
        assertionName = assertion.assertionName
        since = assertion.since
        ignoredBecause = reason
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pid, forKey: .pid)
        try c.encode(process, forKey: .process)
        try c.encode(assertionName, forKey: .assertionName)
        try c.encode(since, forKey: .since)
        try c.encode(ignoredBecause, forKey: .ignoredBecause)
    }
}

public enum FactsSource: String, Codable, Sendable {
    case system
    case fixture
}

/// Raw readings. A null field means that probe did not answer in time (or could not be read).
public struct PresenceFacts: Codable, Equatable, Sendable {
    /// Whether the GUI (Aqua) session could be read at all.
    public var available: Bool
    /// Why the session could not be read, when `available` is false.
    public var unavailableReason: String?
    /// Seconds since the last key press, modifier keys included.
    public var keyIdleSeconds: Double?
    /// Seconds since any keyboard, mouse or trackpad input.
    public var inputIdleSeconds: Double?
    public var locked: Bool?
    public var displaysOnline: Int?
    public var displaysAwake: Int?
    /// Display-sleep assertions that look like media playback, after filters.
    public var video: [VideoAssertion]?
    /// Display-sleep assertions the filters removed, with the reason.
    public var videoIgnored: [IgnoredAssertion]
    /// Null when the audio system did not answer in time.
    public var microphone: Bool?
    /// Null when the camera system did not answer in time.
    public var camera: Bool?
    public var screenSharing: Bool?
    public var source: FactsSource
    public var elapsedMs: Double

    public init(
        available: Bool = true,
        unavailableReason: String? = nil,
        keyIdleSeconds: Double? = 3_600,
        inputIdleSeconds: Double? = 3_600,
        locked: Bool? = false,
        displaysOnline: Int? = 1,
        displaysAwake: Int? = 1,
        video: [VideoAssertion]? = [],
        videoIgnored: [IgnoredAssertion] = [],
        microphone: Bool? = false,
        camera: Bool? = false,
        screenSharing: Bool? = false,
        source: FactsSource = .fixture,
        elapsedMs: Double = 0
    ) {
        self.available = available
        self.unavailableReason = unavailableReason
        self.keyIdleSeconds = keyIdleSeconds
        self.inputIdleSeconds = inputIdleSeconds
        self.locked = locked
        self.displaysOnline = displaysOnline
        self.displaysAwake = displaysAwake
        self.video = video
        self.videoIgnored = videoIgnored
        self.microphone = microphone
        self.camera = camera
        self.screenSharing = screenSharing
        self.source = source
        self.elapsedMs = elapsedMs
    }

    /// Every key is always written; unknown values are written as null.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(available, forKey: .available)
        try c.encode(unavailableReason, forKey: .unavailableReason)
        try c.encode(keyIdleSeconds.map(rounded), forKey: .keyIdleSeconds)
        try c.encode(inputIdleSeconds.map(rounded), forKey: .inputIdleSeconds)
        try c.encode(locked, forKey: .locked)
        try c.encode(displaysOnline, forKey: .displaysOnline)
        try c.encode(displaysAwake, forKey: .displaysAwake)
        try c.encode(video, forKey: .video)
        try c.encode(videoIgnored, forKey: .videoIgnored)
        try c.encode(microphone, forKey: .microphone)
        try c.encode(camera, forKey: .camera)
        try c.encode(screenSharing, forKey: .screenSharing)
        try c.encode(source, forKey: .source)
        try c.encode(rounded(elapsedMs), forKey: .elapsedMs)
    }

    /// Decodes a partial object: missing keys keep the idle defaults; explicit nulls stay null.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        func value<T: Decodable>(_ key: CodingKeys, _ current: T?) throws -> T? {
            guard c.contains(key) else { return current }
            return try c.decodeIfPresent(T.self, forKey: key)
        }
        available = try value(.available, available) ?? true
        unavailableReason = try value(.unavailableReason, unavailableReason)
        keyIdleSeconds = try value(.keyIdleSeconds, keyIdleSeconds)
        inputIdleSeconds = try value(.inputIdleSeconds, inputIdleSeconds)
        locked = try value(.locked, locked)
        displaysOnline = try value(.displaysOnline, displaysOnline)
        displaysAwake = try value(.displaysAwake, displaysAwake)
        video = try value(.video, video)
        videoIgnored = try value(.videoIgnored, videoIgnored) ?? []
        microphone = try value(.microphone, microphone)
        camera = try value(.camera, camera)
        screenSharing = try value(.screenSharing, screenSharing)
        source = try value(.source, source) ?? .fixture
        elapsedMs = try value(.elapsedMs, elapsedMs) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case available, unavailableReason, keyIdleSeconds, inputIdleSeconds, locked
        case displaysOnline, displaysAwake, video, videoIgnored, microphone, camera
        case screenSharing, source, elapsedMs
    }
}

private func rounded(_ value: Double) -> Double {
    (value * 1_000).rounded() / 1_000
}

public enum PresenceState: String, Codable, Sendable {
    case away, idle, typing, video, call
}

/// One classified sample.
public struct Presence: Equatable, Sendable {
    /// Null only when the GUI session is unavailable.
    public var state: PresenceState?
    /// True for typing, video and call; null when unavailable.
    public var busy: Bool?
    public var reason: String
    public var facts: PresenceFacts

    public init(state: PresenceState?, busy: Bool?, reason: String, facts: PresenceFacts) {
        self.state = state
        self.busy = busy
        self.reason = reason
        self.facts = facts
    }

    public var available: Bool { facts.available }
}
