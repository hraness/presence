import Foundation

/// Process exit codes. Documented in the README; keep them stable.
public enum ExitCode: Int32 {
    /// Sampled successfully, or `wait` reached its target state.
    case ok = 0
    /// Runtime failure, such as an unreadable `PRESENCE_FIXTURE`.
    case failure = 1
    /// Bad arguments.
    case usage = 2
    /// The GUI session cannot be read (over ssh, or no Aqua session). `--json` still prints `available: false`.
    case unavailable = 3
    /// `wait` gave up after `--timeout`.
    case timeout = 124
}

public enum Command: Equatable, Sendable {
    case sample
    case watch(everySample: Bool)
    case wait(until: WaitTarget, idleMinutes: Double, timeoutSeconds: Double?)
    case help
    case version
}

public enum WaitTarget: String, Equatable, Sendable {
    /// Idle or away: nothing a run would disturb.
    case idle
    /// Away only: locked, display asleep, or lid closed.
    case away
}

public struct Options: Equatable, Sendable {
    public var command: Command = .sample
    public var json = false
    public var keyIdleMinutes: Double = 5
    public var intervalSeconds: Double = 2
    public var sample = SampleOptions()

    public init() {}
}

public struct UsageError: Error, Equatable, CustomStringConvertible {
    public var description: String
    public init(_ description: String) { self.description = description }
}

public let version = "0.1.0"

public let usage = """
usage: presence [--json] [options]
       presence watch [--json] [--every-sample] [options]
       presence wait --until idle|away [--idle-minutes N] [--timeout DUR] [options]

Reports whether the person at this Mac is using it in a way background work would disturb.
States: away, idle, typing, video, call. Busy means typing, video or call.

options:
  --json                              print JSON (one object; NDJSON for watch)
  --key-idle-minutes N                typing within N minutes counts as typing (default 5)
  --ignore-pids-started-after MS      ignore display assertions from processes started at or after MS (epoch ms)
  --since MS                          ignore display assertions created at or after MS (epoch ms)
  --ignore-tree PID                   ignore display assertions from PID and its descendants (repeatable)
  --ignore-process NAME               treat NAME like the built-in agents (claude, codex, cursor-agent,
                                      xcodebuild): ignore assertions from it and its descendants (repeatable)
  --device-timeout-ms N               give up on the microphone and camera after N ms; report null (default 1500)
  --interval SECONDS                  poll interval for watch and wait (default 2)
  --every-sample                      watch: print every sample, not only state changes
  --until idle|away                   wait: idle accepts idle or away; away accepts only away
  --idle-minutes N                    wait: also require no input of any kind for N minutes (default 0)
  --timeout DUR                       wait: give up after DUR (90, 90s, 500ms, 5m, 1h30m) and exit 124
  -h, --help                          show this help
  --version                           show the version

exit codes: 0 ok, 1 failure, 2 usage, 3 GUI session unavailable, 124 wait timed out
environment: PRESENCE_FIXTURE=<json file> reads facts from a file instead of this Mac
"""

/// Parses arguments (without the program name).
public func parseOptions(_ arguments: [String]) throws -> Options {
    var options = Options()
    var rest = arguments[...]
    var subcommand: String?
    if let first = rest.first, !first.hasPrefix("-") {
        subcommand = first
        rest = rest.dropFirst()
        guard first == "watch" || first == "wait" || first == "help" else {
            throw UsageError("unknown command: \(first)")
        }
    }
    var everySample = false
    var until: WaitTarget?
    var idleMinutes: Double = 0
    var timeout: Double?
    var seen: Set<String> = []

    func next(_ flag: String) throws -> String {
        guard let value = rest.first else { throw UsageError("\(flag) needs a value") }
        rest = rest.dropFirst()
        return value
    }
    func number(_ flag: String, _ text: String, minimum: Double = 0) throws -> Double {
        guard let value = Double(text), value.isFinite, value >= minimum else {
            throw UsageError("\(flag) needs a number of at least \(durationNumber(minimum)), got \(text)")
        }
        return value
    }
    func integer(_ flag: String, _ text: String) throws -> Int64 {
        guard let value = Int64(text), value >= 0 else { throw UsageError("\(flag) needs a non-negative integer, got \(text)") }
        return value
    }

    while let raw = rest.first {
        rest = rest.dropFirst()
        var flag = raw
        // Accept --flag=value as well as --flag value.
        if raw.hasPrefix("--"), let equals = raw.firstIndex(of: "=") {
            flag = String(raw[..<equals])
            rest = [String(raw[raw.index(after: equals)...])] + rest
        }
        if flag != "--ignore-tree", flag != "--ignore-process", seen.contains(flag) { throw UsageError("\(flag) given twice") }
        seen.insert(flag)
        switch flag {
        case "-h", "--help": options.command = .help; return options
        case "--version": options.command = .version; return options
        case "--json": options.json = true
        case "--key-idle-minutes": options.keyIdleMinutes = try number(flag, next(flag))
        case "--ignore-pids-started-after": options.sample.filter.ignorePidsStartedAfter = try integer(flag, next(flag))
        case "--since": options.sample.filter.since = try integer(flag, next(flag))
        case "--ignore-tree":
            let text = try next(flag)
            guard let pid = Int32(text), pid > 0 else { throw UsageError("--ignore-tree needs a pid, got \(text)") }
            options.sample.filter.ignoreTrees.append(pid)
        case "--ignore-process":
            let name = try next(flag)
            guard !name.isEmpty else { throw UsageError("--ignore-process needs a process name") }
            options.sample.filter.ignoreProcesses.append(name)
        case "--device-timeout-ms":
            let value = try integer(flag, next(flag))
            guard value >= 1, value <= 600_000 else { throw UsageError("--device-timeout-ms must be between 1 and 600000") }
            options.sample.deviceTimeoutMs = Int(value)
        case "--interval": options.intervalSeconds = try number(flag, next(flag), minimum: 0.1)
        case "--every-sample": everySample = true
        case "--until":
            let text = try next(flag)
            guard let target = WaitTarget(rawValue: text) else { throw UsageError("--until must be idle or away, got \(text)") }
            until = target
        case "--idle-minutes": idleMinutes = try number(flag, next(flag))
        case "--timeout":
            let text = try next(flag)
            guard let seconds = parseDuration(text) else { throw UsageError("--timeout needs a duration like 90s, 5m or 1h30m, got \(text)") }
            timeout = seconds
        default:
            throw UsageError("unknown option: \(raw)")
        }
    }

    let waitOnly = ["--until", "--idle-minutes", "--timeout"].filter(seen.contains)
    let watchOnly = ["--every-sample"].filter(seen.contains)
    switch subcommand {
    case nil:
        if let flag = (waitOnly + watchOnly + (seen.contains("--interval") ? ["--interval"] : [])).first {
            throw UsageError("\(flag) needs the \(waitOnly.contains(flag) ? "wait" : "watch") command")
        }
    case "help":
        options.command = .help
    case "watch":
        if let flag = waitOnly.first { throw UsageError("\(flag) needs the wait command") }
        options.command = .watch(everySample: everySample)
    case "wait":
        if let flag = watchOnly.first { throw UsageError("\(flag) needs the watch command") }
        guard let until else { throw UsageError("wait needs --until idle|away") }
        options.command = .wait(until: until, idleMinutes: idleMinutes, timeoutSeconds: timeout)
    default:
        break
    }
    return options
}

private func durationNumber(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(value)
}

/// Seconds in `90`, `90s`, `500ms`, `5m`, `2h`, `1h30m`, `1.5h`; nil when malformed.
public func parseDuration(_ text: String) -> Double? {
    if let plain = Double(text), plain.isFinite, plain >= 0 { return plain }
    var total = 0.0
    var number = ""
    var index = text.startIndex
    var parts = 0
    while index < text.endIndex {
        let character = text[index]
        if character.isNumber || character == "." {
            number.append(character)
            index = text.index(after: index)
            continue
        }
        var unit = String(character)
        index = text.index(after: index)
        if unit == "m", index < text.endIndex, text[index] == "s" {
            unit = "ms"
            index = text.index(after: index)
        }
        guard let value = Double(number), value.isFinite else { return nil }
        let scale: Double
        switch unit {
        case "ms": scale = 0.001
        case "s": scale = 1
        case "m": scale = 60
        case "h": scale = 3_600
        case "d": scale = 86_400
        default: return nil
        }
        total += value * scale
        number = ""
        parts += 1
    }
    guard number.isEmpty, parts > 0 else { return nil }
    return total
}
