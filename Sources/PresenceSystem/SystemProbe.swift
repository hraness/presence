import CoreGraphics
import Foundation
import IOKit.pwr_mgt
import PresenceCore

/// Reads this Mac. Every probe runs off the calling thread with a deadline; none needs a
/// privacy prompt or TCC grant. Keep one instance for repeated samples: its probes stay warm.
public final class SystemProbe: FactsProbe {
    private struct Session { var locked: Bool }
    private struct Idle { var key: Double; var input: Double }
    private struct Displays { var online: Int; var awake: Int }

    private let session = TimedProbe<Session?>("session") {
        // Nil outside a GUI (Aqua) session, such as over ssh or from a launch daemon.
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else { return .some(nil) }
        return Session(locked: (dictionary["CGSSessionScreenIsLocked"] as? Bool) ?? false)
    }

    private let idle = TimedProbe<Idle>("idle") {
        // HID system state counts hardware input only, and needs no Input Monitoring grant.
        let source = CGEventSourceStateID.hidSystemState
        let key = min(
            CGEventSource.secondsSinceLastEventType(source, eventType: .keyDown),
            CGEventSource.secondsSinceLastEventType(source, eventType: .flagsChanged)
        )
        // kCGAnyInputEventType is ~0.
        let any = CGEventType(rawValue: ~0) ?? .null
        return Idle(key: key, input: CGEventSource.secondsSinceLastEventType(source, eventType: any))
    }

    private let displays = TimedProbe<Displays>("displays") {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return nil }
        let online = ids.prefix(Int(count))
        return Displays(online: online.count, awake: online.filter { CGDisplayIsAsleep($0) == 0 }.count)
    }

    private let assertions = TimedProbe<[RawAssertion]>("assertions") { readAssertions() }
    private let sharing = TimedProbe<Bool>("sharing") { processRunning("screensharingd") }
    private let microphone = TimedProbe<Bool>("microphone") { microphoneInUse() }
    private let camera = TimedProbe<Bool>("camera") { cameraInUse() }

    public init() {}

    public func sample(_ options: SampleOptions) -> PresenceFacts {
        let started = DispatchTime.now().uptimeNanoseconds
        let timeout = options.probeTimeoutMs
        // Kick off the slow device reads first so they overlap with everything else.
        let group = DispatchGroup()
        var mic: Bool?
        var cam: Bool?
        DispatchQueue.global(qos: .userInitiated).async(group: group) { [microphone] in
            mic = microphone.read(timeoutMs: options.deviceTimeoutMs)
        }
        DispatchQueue.global(qos: .userInitiated).async(group: group) { [camera] in
            cam = camera.read(timeoutMs: options.deviceTimeoutMs)
        }

        var facts = PresenceFacts(source: .system)
        switch session.read(timeoutMs: timeout) {
        case .none:
            facts.locked = nil
        case .some(.none):
            facts.available = false
            facts.unavailableReason = "no GUI session (over ssh, or no one logged in at the console)"
        case .some(.some(let value)):
            facts.locked = value.locked
        }
        let idleValue = idle.read(timeoutMs: timeout)
        facts.keyIdleSeconds = idleValue?.key
        facts.inputIdleSeconds = idleValue?.input
        let displayValue = displays.read(timeoutMs: timeout)
        facts.displaysOnline = displayValue?.online
        facts.displaysAwake = displayValue?.awake
        facts.screenSharing = sharing.read(timeoutMs: timeout)
        if let raw = assertions.read(timeoutMs: timeout) {
            let split = filterVideo(raw, options: options.filter, processInfo: processInfo)
            facts.video = split.video
            facts.videoIgnored = split.ignored
        } else {
            facts.video = nil
        }

        // Both device reads return within their own deadline.
        group.wait()
        facts.microphone = mic
        facts.camera = cam
        facts.elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        return facts
    }
}

/// User-space power assertions by owning process (what `pmset -g assertions` lists by process).
private func readAssertions() -> [RawAssertion]? {
    var unmanaged: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess, let byPid = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else {
        return nil
    }
    var found: [RawAssertion] = []
    for (pid, list) in byPid {
        for entry in list {
            guard let type = entry["AssertType"] as? String else { continue }
            let trueType = entry["AssertionTrueType"] as? String
            let since = (entry["AssertStartWhen"] as? Date).map { Int64(($0.timeIntervalSince1970 * 1_000).rounded()) }
            found.append(RawAssertion(
                pid: (entry["AssertPID"] as? NSNumber)?.int32Value ?? pid.int32Value,
                process: entry["Process Name"] as? String,
                assertionName: entry["AssertName"] as? String ?? "",
                type: type,
                trueType: trueType == type ? nil : trueType,
                since: since
            ))
        }
    }
    return found
}
