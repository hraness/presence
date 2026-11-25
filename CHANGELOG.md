# Changelog

## 0.1.0 (unreleased)

- First version: `presence`, `presence --json`, `presence watch [--json] [--every-sample]` and
  `presence wait --until idle|away`.
- Reads idle time, lock, displays, microphone, camera, display-sleep assertions and screen sharing
  through system APIs, with a deadline on every probe and no privacy prompts.
- JSON schema version 1, with raw facts, `video` and `videoIgnored`.
- `PRESENCE_FIXTURE` for tests and CI.
