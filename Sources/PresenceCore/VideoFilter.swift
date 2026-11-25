import Foundation

/// A power assertion as IOKit reports it, before any filtering.
public struct RawAssertion: Codable, Equatable, Sendable {
    public var pid: Int32
    /// IOPM's "Process Name", if it gave one.
    public var process: String?
    public var assertionName: String
    /// `AssertType`.
    public var type: String
    /// `AssertionTrueType`, when it differs from `type`.
    public var trueType: String?
    /// `AssertStartWhen` in ms since the Unix epoch.
    public var since: Int64?

    public init(pid: Int32, process: String?, assertionName: String, type: String, trueType: String? = nil, since: Int64?) {
        self.pid = pid
        self.process = process
        self.assertionName = assertionName
        self.type = type
        self.trueType = trueType
        self.since = since
    }
}

public struct ProcessInfoRecord: Codable, Equatable, Sendable {
    public var name: String
    public var ppid: Int32
    public var startedAtMs: Int64

    public init(name: String, ppid: Int32, startedAtMs: Int64) {
        self.name = name
        self.ppid = ppid
        self.startedAtMs = startedAtMs
    }
}

/// Which assertions to leave out on top of the built-in keep-awake and agent lists.
public struct VideoFilterOptions: Equatable, Sendable {
    /// Ignore assertions whose owner started at or after this time (ms since epoch).
    public var ignorePidsStartedAfter: Int64?
    /// Ignore assertions created at or after this time (ms since epoch).
    public var since: Int64?
    /// Ignore assertions owned by these pids or their descendants.
    public var ignoreTrees: [Int32]
    /// Process names added to `agentProcesses` for this sample (`--ignore-process`).
    public var ignoreProcesses: [String]

    public init(ignorePidsStartedAfter: Int64? = nil, since: Int64? = nil, ignoreTrees: [Int32] = [], ignoreProcesses: [String] = []) {
        self.ignorePidsStartedAfter = ignorePidsStartedAfter
        self.since = since
        self.ignoreTrees = ignoreTrees
        self.ignoreProcesses = ignoreProcesses
    }
}

/// Utilities that keep the display awake on purpose; never a sign of video.
public let keepAwakeProcesses: Set<String> = [
    "Amphetamine",
    "Amphetamine Enhancer",
    "caffeinate",
    "KeepingYouAwake",
    "Lungo",
    "powerd",
    "Theine",
]

/// Assertions owned by a process under one of these come from agents and builds.
/// Extend it per call with `--ignore-process NAME`.
public let agentProcesses: Set<String> = [
    "claude",
    "codex",
    "cursor-agent",
    "xcodebuild",
]

/// Assertion types that keep the display on.
public let displaySleepTypes: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]

/// Splits display-sleep assertions into video and ignored. Other assertion types are dropped.
public func filterVideo(
    _ assertions: [RawAssertion],
    options: VideoFilterOptions = VideoFilterOptions(),
    processInfo: (Int32) -> ProcessInfoRecord?
) -> (video: [VideoAssertion], ignored: [IgnoredAssertion]) {
    var memo: [Int32: ProcessInfoRecord?] = [:]
    func info(_ pid: Int32) -> ProcessInfoRecord? {
        if let known = memo[pid] { return known }
        let found = processInfo(pid)
        memo[pid] = found
        return found
    }
    /// The pid itself, then its ancestors, until init or an unknown process.
    func lineage(_ pid: Int32) -> [(pid: Int32, info: ProcessInfoRecord)] {
        var chain: [(Int32, ProcessInfoRecord)] = []
        var current = pid
        for _ in 0..<64 where current > 1 {
            guard let record = info(current) else { break }
            chain.append((current, record))
            current = record.ppid
        }
        return chain
    }

    var video: [VideoAssertion] = []
    var ignored: [IgnoredAssertion] = []
    let trees = Set(options.ignoreTrees)
    let agents = agentProcesses.union(options.ignoreProcesses)
    for raw in assertions {
        guard displaySleepTypes.contains(raw.type) || raw.trueType.map(displaySleepTypes.contains) == true else { continue }
        let owner = info(raw.pid)
        let entry = VideoAssertion(
            pid: raw.pid,
            process: owner?.name ?? raw.process ?? "pid \(raw.pid)",
            assertionName: raw.assertionName,
            since: raw.since
        )
        let chain = lineage(raw.pid)
        let reason: IgnoreReason?
        if keepAwakeProcesses.contains(entry.process) || raw.process.map(keepAwakeProcesses.contains) == true {
            reason = .keepAwake
        } else if let since = options.since, let created = raw.since, created >= since {
            reason = .since
        } else if let after = options.ignorePidsStartedAfter, let owner, owner.startedAtMs >= after {
            reason = .startedAfter
        } else if !trees.isEmpty, chain.contains(where: { trees.contains($0.pid) }) || trees.contains(raw.pid) {
            reason = .ignoredTree
        } else if chain.contains(where: { agents.contains($0.info.name) }) {
            reason = .agent
        } else {
            reason = nil
        }
        if let reason {
            ignored.append(IgnoredAssertion(entry, because: reason))
        } else {
            video.append(entry)
        }
    }
    // Oldest first, so output is stable across samples.
    video.sort { ($0.since ?? 0, $0.pid, $0.assertionName) < ($1.since ?? 0, $1.pid, $1.assertionName) }
    ignored.sort { ($0.since ?? 0, $0.pid, $0.assertionName) < ($1.since ?? 0, $1.pid, $1.assertionName) }
    return (video, ignored)
}
