# Changelog

## 0.1.0 (2026-11-25)

- First version: `presence`, `presence --json`, `presence watch [--json] [--every-sample]` and
  `presence wait --until idle|away`.
- Reads idle time, lock, displays, microphone, camera, display-sleep assertions and screen sharing
  through system APIs, with a deadline on every probe and no privacy prompts.
- JSON schema version 1, with raw facts, `video` and `videoIgnored`.
- `PRESENCE_FIXTURE` for tests and CI.
- Built-in agent filter covers claude, codex, cursor-agent and xcodebuild; `--ignore-process NAME`
  (repeatable) adds more.
- Release workflow: universal tarball, sha256 and build provenance attestation on a `v*` tag.
