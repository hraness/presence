import Foundation

/// Turns raw facts into one state with a short reason.
///
/// Order matters: away beats everything, then calls, then video, then typing.
/// A fact that is null (its probe did not answer) always errs toward busy,
/// because a run that might disturb a call is not worth the risk.
public func classify(_ facts: PresenceFacts, keyIdleMinutes: Double) -> Presence {
    func result(_ state: PresenceState, _ reason: String) -> Presence {
        Presence(state: state, busy: state == .typing || state == .video || state == .call, reason: reason, facts: facts)
    }
    guard facts.available else {
        return Presence(state: nil, busy: nil, reason: facts.unavailableReason ?? "GUI session unavailable", facts: facts)
    }
    if facts.locked == true { return result(.away, "screen locked") }
    if facts.displaysOnline == 0 { return result(.away, "lid closed with no display") }
    if facts.displaysAwake == 0 { return result(.away, "display asleep") }
    if facts.camera == true { return result(.call, "camera in use") }
    if facts.camera == nil || facts.microphone == nil {
        return result(.call, "microphone or camera state unknown")
    }
    switch facts.screenSharing {
    case .some(true): return result(.call, "screen sharing")
    case .none: return result(.call, "screen sharing state unknown")
    case .some(false): break
    }
    if facts.microphone == true { return result(.call, "microphone in use") }
    guard let video = facts.video else { return result(.video, "video state unknown") }
    if let first = video.first { return result(.video, "video playing in \(first.process)") }
    guard let keyIdle = facts.keyIdleSeconds else { return result(.typing, "key idle time unknown") }
    if keyIdle < keyIdleMinutes * 60 { return result(.typing, "typed \(durationText(keyIdle)) ago") }
    return result(.idle, "owner idle \(durationText(keyIdle)), no video or call")
}

/// `42s`, `7m`, `2h05m`.
public func durationText(_ seconds: Double) -> String {
    if seconds < 60 { return "\(Int(max(0, seconds.rounded(.down))))s" }
    let minutes = Int(seconds / 60)
    if minutes < 60 { return "\(minutes)m" }
    return "\(minutes / 60)h" + String(format: "%02dm", minutes % 60)
}
