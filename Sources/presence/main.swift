import Foundation
import PresenceCore
import PresenceSystem

setvbuf(stdout, nil, _IOLBF, 0)
// A closed pipe (presence watch | head -1) should end the process quietly.
signal(SIGPIPE, SIG_DFL)

func fail(_ message: String, _ code: ExitCode) -> Never {
    FileHandle.standardError.write(Data("presence: \(message)\n".utf8))
    exit(code.rawValue)
}

let options: Options
do {
    options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("presence: \(error)\n\n\(usage)\n".utf8))
    exit(ExitCode.usage.rawValue)
}

switch options.command {
case .help:
    print(usage)
    exit(ExitCode.ok.rawValue)
case .version:
    print("presence \(version)")
    exit(ExitCode.ok.rawValue)
default:
    break
}

let probe: FactsProbe
if let fixture = ProcessInfo.processInfo.environment["PRESENCE_FIXTURE"], !fixture.isEmpty {
    let fixtureProbe = FixtureProbe(path: fixture)
    do {
        _ = try fixtureProbe.load(options.sample)
    } catch {
        fail("\(error)", .failure)
    }
    probe = fixtureProbe
} else {
    probe = SystemProbe()
}

func sample() -> Presence {
    classify(probe.sample(options.sample), keyIdleMinutes: options.keyIdleMinutes)
}

func emit(_ presence: Presence) {
    print(options.json ? jsonLine(presence) : humanLine(presence))
}

let clock = { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }
let environment = LoopEnvironment(
    sample: sample,
    now: clock,
    sleep: { seconds in Thread.sleep(forTimeInterval: seconds) },
    emit: emit
)

switch options.command {
case .sample:
    let presence = sample()
    emit(presence)
    exit(presence.available ? ExitCode.ok.rawValue : ExitCode.unavailable.rawValue)
case .watch(let everySample):
    watch(everySample: everySample, interval: options.intervalSeconds, environment: environment)
    exit(ExitCode.ok.rawValue)
case .wait(let until, let idleMinutes, let timeout):
    let code = wait(until: until, idleMinutes: idleMinutes, timeout: timeout, interval: options.intervalSeconds, environment: environment)
    exit(code.rawValue)
case .help, .version:
    exit(ExitCode.ok.rawValue)
}
