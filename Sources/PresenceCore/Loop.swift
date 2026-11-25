import Foundation

/// Side effects the loops need, injectable so tests run on a fake clock.
public struct LoopEnvironment {
    public var sample: () -> Presence
    /// Monotonic seconds.
    public var now: () -> Double
    public var sleep: (Double) -> Void
    public var emit: (Presence) -> Void

    public init(sample: @escaping () -> Presence, now: @escaping () -> Double, sleep: @escaping (Double) -> Void, emit: @escaping (Presence) -> Void) {
        self.sample = sample
        self.now = now
        self.sleep = sleep
        self.emit = emit
    }
}

/// What counts as a change for `watch`: the state, or the session becoming (un)available.
func changeKey(_ presence: Presence) -> String {
    presence.state?.rawValue ?? "unavailable"
}

/// Prints the first sample, then each state change (or every sample). Returns after `maxSamples`, if set.
public func watch(everySample: Bool, interval: Double, environment env: LoopEnvironment, maxSamples: Int? = nil) {
    var last: String?
    var count = 0
    while maxSamples.map({ count < $0 }) ?? true {
        let started = env.now()
        let presence = env.sample()
        count += 1
        let key = changeKey(presence)
        if everySample || key != last {
            env.emit(presence)
            last = key
        }
        if let maxSamples, count >= maxSamples { break }
        // Sleep the rest of the interval so a slow sample does not stretch the cadence.
        env.sleep(max(0.05, interval - (env.now() - started)))
    }
}

/// Whether a sample satisfies `wait`.
public func reached(_ presence: Presence, until: WaitTarget, idleMinutes: Double) -> Bool {
    guard let state = presence.state else { return false }
    let stateOK: Bool
    switch until {
    case .idle: stateOK = state == .idle || state == .away
    case .away: stateOK = state == .away
    }
    guard stateOK else { return false }
    if idleMinutes <= 0 { return true }
    // Away means nobody can be at the keyboard; only an unlocked idle screen needs the input check.
    if state == .away { return true }
    guard let input = presence.facts.inputIdleSeconds else { return false }
    return input >= idleMinutes * 60
}

/// Polls until the target is reached (0), the timeout passes (124) or the session is unavailable (3).
public func wait(until: WaitTarget, idleMinutes: Double, timeout: Double?, interval: Double, environment env: LoopEnvironment) -> ExitCode {
    let start = env.now()
    while true {
        let started = env.now()
        let presence = env.sample()
        if !presence.available {
            env.emit(presence)
            return .unavailable
        }
        if reached(presence, until: until, idleMinutes: idleMinutes) {
            env.emit(presence)
            return .ok
        }
        let elapsed = env.now() - start
        if let timeout, elapsed >= timeout {
            env.emit(presence)
            return .timeout
        }
        var pause = max(0.05, interval - (env.now() - started))
        if let timeout { pause = min(pause, max(0, timeout - elapsed)) }
        env.sleep(pause)
    }
}
