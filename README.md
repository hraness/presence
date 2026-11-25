# presence

[![CI](https://github.com/hraness/presence/actions/workflows/ci.yml/badge.svg)](https://github.com/hraness/presence/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Tiny macOS CLI that tells you whether someone is using this Mac: away, idle, typing, watching video or on a call.

Use it to gate builds, tests, backups, notifications and agent work so they never interrupt you. It reads macOS system APIs directly (input idle time, screen lock, displays, microphone, camera, power assertions, screen sharing) and prints one answer. No permissions or prompts, no daemon, no dependencies: one ~600 KB universal binary for macOS 13 and later.

## Install

```sh
curl -fsSL https://github.com/hraness/presence/releases/download/v0.1.0/presence-0.1.0-macos-universal.tar.gz | tar -xz
sudo install presence-0.1.0-macos-universal/presence /usr/local/bin/
swift build -c release              # from source: .build/release/presence
```

Releases include a `.sha256` file and a build provenance attestation (`gh attestation verify <tarball> --repo hraness/presence`).

## Usage

```sh
presence                                   # typing: typed 4s ago
presence --json | jq -r .state             # idle
presence wait --until idle && make         # run the build once nobody is typing, watching or calling
presence watch --json                      # one JSON line per state change
presence wait --until away --timeout 50m && restic backup ~   # from an hourly LaunchAgent; cron may not see the GUI session
if presence wait --until idle --timeout 0; then brew upgrade; else echo later; fi   # 0 = idle now, 124 = busy
```

| State | Meaning | Busy |
| --- | --- | --- |
| `away` | screen locked, display asleep, or lid closed | no |
| `idle` | unlocked, but no key pressed for 5 minutes (`--key-idle-minutes`) | no |
| `typing` | a key pressed recently | yes |
| `video` | something holds the display awake, like a video player (keep-awake tools and agents are filtered) | yes |
| `call` | camera, microphone or screen sharing in use | yes |

Exit codes: 0 ok, 1 failure, 2 bad arguments, 3 no GUI session (for example over ssh), 124 `wait` timed out. Every option, the JSON schema (`schemaVersion: 1`) and the fixture format for tests are in [docs/reference.md](docs/reference.md).

## Compared with

[beengone](https://brettterpstra.com/projects/beengone/) reports idle time only; [dstat](https://github.com/luckman212/dstat) and [amiunlocked](https://github.com/raygesualdo/amiunlocked) report lock state only; [OverSight](https://objective-see.org/products/oversight.html), [On Air](https://github.com/maxchuquimia/onair) and Micro Snitch are GUI apps for the microphone or camera; [available](https://github.com/jonesiscoding/available) covers interruptibility but needs root and reads files. presence reads all of these signals in one call, with no root and no prompts.

## FAQ

**How do I check if my Mac is idle from the command line?**
Run `presence`; it prints `idle` when nobody has typed for 5 minutes, or use `presence --json | jq .facts.inputIdleSeconds` for the raw seconds since any input.

**How do I detect if the camera or microphone is in use on macOS?**
`presence --json | jq '.facts | {camera, microphone}'` reads CoreAudio and CoreMediaIO "running somewhere" flags, which need no camera or microphone permission.

**How do I run a command only when I'm away from my Mac?**
`presence wait --until away && your-command` blocks until the screen locks or the display sleeps; add `--timeout 1h` to give up (exit 124).

**Does it need Accessibility, Input Monitoring or root?**
No. Every signal comes from an API that works without a TCC grant, so it never shows a prompt.

## Contributing

Issues and pull requests are welcome; `scripts/test.sh` (swift test with Xcode) must pass. Security reports: see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
