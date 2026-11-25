# presence reference

Everything the [README](../README.md) leaves out: what each fact is read from, how a state is
chosen, every option, exit codes, the JSON schema and fixtures.

## What it reads

Every signal comes from a system API. Nothing shells out, and **nothing needs a privacy prompt or
TCC grant** (no Accessibility, Input Monitoring, Microphone, Camera or Screen Recording).

| Fact | Source |
| --- | --- |
| `keyIdleSeconds` | `CGEventSourceSecondsSinceLastEventType(hidSystemState, keyDown / flagsChanged)` |
| `inputIdleSeconds` | the same, for any input event (keys, mouse, trackpad) |
| `locked` | `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]` |
| `displaysOnline`, `displaysAwake` | `CGGetOnlineDisplayList`, `CGDisplayIsAsleep` |
| `microphone` | CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere` on devices with input streams |
| `camera` | CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere` |
| `video`, `videoIgnored` | `IOPMCopyAssertionsByProcess`, display-sleep assertions only |
| `screenSharing` | whether `screensharingd` is running (one `sysctl` over the process table) |

The microphone and camera flags say that a device is open somewhere, not what it hears or sees.

Each probe runs off the main thread with a deadline. A probe that misses it is abandoned (the next
sample waits for that same read rather than starting another) and its fact is reported as `null`.
The CoreAudio and CoreMediaIO reads can stall for many seconds on a loaded Mac, so they have their own
deadline, `--device-timeout-ms` (default 1500). A first sample takes about 40 ms; warm samples inside
`watch` cost about 5 ms.

### Video filters

A display-sleep assertion (`PreventUserIdleDisplaySleep`, `NoDisplaySleepAssertion`) usually means
media is playing. Some are not, and land in `videoIgnored` with a reason instead:

| `ignoredBecause` | When |
| --- | --- |
| `keep-awake` | the owner is a keep-awake utility: Amphetamine, Amphetamine Enhancer, caffeinate, KeepingYouAwake, Lungo, powerd, Theine |
| `since` | the assertion was created at or after `--since` |
| `started-after` | the owning process started at or after `--ignore-pids-started-after` |
| `ignored-tree` | the owner is a pid passed to `--ignore-tree`, or descends from one |
| `agent` | the owner is, or descends from, claude, codex, cursor-agent, xcodebuild, or a name passed to `--ignore-process` |

The first matching reason wins, in that order.

## How a state is chosen

First match wins. Unknown (`null`) facts err toward busy.

1. `away`: screen locked, no display online (lid closed), or every display asleep.
2. `call`: camera on; microphone or camera unknown; screen sharing (or unknown); microphone on.
3. `video`: a display-sleep assertion survives the filters, or assertions could not be read.
4. `typing`: a key within `--key-idle-minutes` (default 5), or key idle time unknown.
5. `idle`: otherwise.

`busy` is true for `typing`, `video` and `call`. Mouse movement alone does not count as typing; use
`inputIdleSeconds` or `wait --idle-minutes` for that.

## Usage

```
presence [--json] [options]
presence watch [--json] [--every-sample] [options]
presence wait --until idle|away [--idle-minutes N] [--timeout DUR] [options]
```

| Option | Meaning |
| --- | --- |
| `--json` | print JSON: one object, or NDJSON (one object per line) for `watch` |
| `--key-idle-minutes N` | a key press within N minutes counts as typing (default 5) |
| `--ignore-pids-started-after MS` | ignore display assertions from processes started at or after MS (epoch ms) |
| `--since MS` | ignore display assertions created at or after MS (epoch ms) |
| `--ignore-tree PID` | ignore display assertions from PID and its descendants; repeatable |
| `--ignore-process NAME` | add NAME to the built-in agent list (reason `agent`), so its assertions and its descendants' are ignored; repeatable |
| `--device-timeout-ms N` | deadline for the microphone and camera reads (default 1500) |
| `--interval SECONDS` | poll interval for `watch` and `wait` (default 2) |
| `--every-sample` | `watch`: print every sample, not only state changes |
| `--until idle\|away` | `wait`: `idle` is satisfied by idle or away; `away` only by away |
| `--idle-minutes N` | `wait`: also require no input of any kind for N minutes while unlocked (default 0) |
| `--timeout DUR` | `wait`: give up after DUR (`90`, `90s`, `500ms`, `5m`, `1h30m`) |

`watch` prints the first sample, then a line each time the state changes (or every sample with
`--every-sample`). It sleeps between samples; one long-lived `watch --json --every-sample` is the
cheapest way to poll every 2 s. `wait` prints the final sample when it exits.

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | sampled (or `wait` reached its target) |
| 1 | runtime failure, such as an unreadable `PRESENCE_FIXTURE` |
| 2 | bad arguments |
| 3 | the GUI session cannot be read (over ssh, or no one logged in at the console); `--json` still prints `available: false` |
| 124 | `wait` timed out |

`watch` keeps running when the session becomes unavailable and reports it as a state change.

## JSON (schema version 1)

```json
{
  "available": true,
  "busy": false,
  "facts": {
    "available": true,
    "camera": false,
    "displaysAwake": 1,
    "displaysOnline": 1,
    "elapsedMs": 4.6,
    "inputIdleSeconds": 412.08,
    "keyIdleSeconds": 412.08,
    "locked": false,
    "microphone": false,
    "screenSharing": false,
    "source": "system",
    "unavailableReason": null,
    "video": [],
    "videoIgnored": [
      { "assertionName": "Amphetamine (Single-Use - Display)", "ignoredBecause": "keep-awake",
        "pid": 1908, "process": "Amphetamine", "since": 1795434761724 }
    ]
  },
  "reason": "owner idle 6m, no video or call",
  "sampledAt": 1795646489135,
  "schemaVersion": 1,
  "state": "idle"
}
```

| Field | Type | Notes |
| --- | --- | --- |
| `schemaVersion` | `1` | bumped on any breaking change |
| `available` | bool | false when the GUI session cannot be read |
| `state` | `"away" \| "idle" \| "typing" \| "video" \| "call" \| null` | null only when unavailable |
| `busy` | bool or null | true for typing, video, call; null when unavailable |
| `reason` | string | short human reason; wording may change, do not parse it |
| `sampledAt` | int | epoch ms |
| `facts.keyIdleSeconds`, `facts.inputIdleSeconds` | number or null | |
| `facts.locked` | bool or null | |
| `facts.displaysOnline`, `facts.displaysAwake` | int or null | |
| `facts.microphone`, `facts.camera`, `facts.screenSharing` | bool or null | null: did not answer in time |
| `facts.video` | array or null | `{pid, process, assertionName, since}`, after filters; `since` is `AssertStartWhen` in epoch ms or null |
| `facts.videoIgnored` | array | the same fields plus `ignoredBecause` |
| `facts.source` | `"system" \| "fixture"` | |
| `facts.elapsedMs` | number | time the sample took |
| `facts.available`, `facts.unavailableReason` | bool, string or null | |

Every key is always present; unknown values are `null`, never missing. Keys are sorted. New fields
may be added within version 1.

## Testing without a live machine

`PRESENCE_FIXTURE=<file.json>` replaces every probe with a JSON file of facts, reread on every
sample, so `watch` and `wait` can be driven by rewriting it. Missing keys take idle defaults. A
fixture can also carry raw `assertions` and a `processes` table, and then the video filters run on
them; see `Tests/PresenceCoreTests/Fixtures/`.

```console
$ echo '{"camera": true}' > /tmp/call.json
$ PRESENCE_FIXTURE=/tmp/call.json presence
call: camera in use
```

## Building

```sh
swift build -c release
scripts/test.sh            # swift test with an Xcode toolchain (swift-testing is not in the Command Line Tools)
./scripts/release.sh       # universal arm64 + x86_64 binary and tarball with sha256 in dist/
```

