import Foundation
import Testing

/// The built binary: `PRESENCE_BIN`, or the `presence` product next to the test bundle in `.build`.
private let binary: URL? = {
    if let path = ProcessInfo.processInfo.environment["PRESENCE_BIN"], !path.isEmpty {
        return URL(fileURLWithPath: path)
    }
    // The resource bundle sits in or beside the products directory, depending on the build system.
    var directory = Bundle.module.bundleURL.deletingLastPathComponent()
    for _ in 0..<4 {
        let candidate = directory.appendingPathComponent("presence")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue,
           FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        directory.deleteLastPathComponent()
    }
    return nil
}()

private func fixturePath(_ name: String) -> String {
    Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!.path
}

/// Runs `presence` with `PRESENCE_FIXTURE` set, so nothing here reads the live machine.
private func run(_ arguments: [String], fixture: String) throws -> (code: Int32, out: String) {
    let process = Process()
    guard let binary else {
        Issue.record("presence binary not found; set PRESENCE_BIN or run swift build")
        return (-1, "")
    }
    process.executableURL = binary
    process.arguments = arguments
    process.environment = ["PRESENCE_FIXTURE": fixture.hasPrefix("/") ? fixture : fixturePath(fixture)]
    let out = Pipe()
    process.standardOutput = out
    process.standardError = Pipe()
    try process.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

private func object(_ text: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

@Suite
struct CLITests {
    @Test func humanLine() throws {
        let result = try run([], fixture: "typing")
        #expect(result.code == 0)
        #expect(result.out == "typing: typed 12s ago\n")
    }

    @Test func json() throws {
        let result = try run(["--json"], fixture: "idle")
        #expect(result.code == 0)
        let parsed = try object(result.out)
        #expect(parsed["state"] as? String == "idle")
        #expect(parsed["busy"] as? Bool == false)
        #expect((parsed["facts"] as? [String: Any])?["source"] as? String == "fixture")
    }

    @Test func unavailableExitsThree() throws {
        let result = try run(["--json"], fixture: "unavailable")
        #expect(result.code == 3)
        #expect(result.out.contains("\"available\":false"))
    }

    @Test func usageExitsTwo() throws {
        #expect(try run(["--bogus"], fixture: "idle").code == 2)
    }

    @Test func missingFixtureExitsOne() throws {
        #expect(try run([], fixture: "/nonexistent/presence.json").code == 1)
    }

    @Test func waitReachedAndTimeout() throws {
        #expect(try run(["wait", "--until", "idle", "--timeout", "1s", "--interval", "0.1"], fixture: "idle").code == 0)
        let timedOut = try run(["wait", "--until", "away", "--timeout", "300ms", "--interval", "0.1", "--json"], fixture: "idle")
        #expect(timedOut.code == 124)
        #expect(timedOut.out.contains("\"state\":\"idle\""))
    }

    @Test func ignoreTreeFlag() throws {
        let parsed = try object(try run(["--json", "--ignore-tree", "499", "--ignore-tree", "790"], fixture: "assertions").out)
        #expect(parsed["state"] as? String == "idle")
        let ignored = try #require((parsed["facts"] as? [String: Any])?["videoIgnored"] as? [[String: Any]])
        #expect(ignored.compactMap { $0["ignoredBecause"] as? String } == ["keep-awake", "ignored-tree", "agent", "ignored-tree"])
    }

    @Test func ignoreProcessFlag() throws {
        let parsed = try object(try run(["--json", "--ignore-process", "xctest-runner"], fixture: "assertions").out)
        #expect(parsed["reason"] as? String == "video playing in Google Chrome Helper")
        let ignored = try #require((parsed["facts"] as? [String: Any])?["videoIgnored"] as? [[String: Any]])
        #expect(ignored.compactMap { $0["ignoredBecause"] as? String } == ["keep-awake", "agent", "agent"])
    }
}
