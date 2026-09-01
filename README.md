# Ajar

**Close your MacBook halfway. Your mic mutes. Open it. It's back.**

Ajar is a macOS menu-bar utility that turns the lid-angle sensor of your
MacBook into a control surface:

- **Nudge the lid down** (didn't close it, just tilted it) → microphone mutes,
  with honest restore — it only un-mutes what it muted, and never touches a
  mic you silenced yourself.
- **Push the lid to the stop** → runs a Shortcut. Default is Do Not Disturb;
  point it at anything Shortcuts can do.

No Accessibility prompt. No private APIs — the sensor is read through the
public `IOHIDManager` (HID usage page `0x20`, usage `0x8A`). No analytics, no
telemetry. The network is touched in exactly two places: license activation
and Sparkle update checks.

## Status

This repository ships the **free build**. Everything is unlocked. A paid Pro
tier (custom Shortcuts on the stop zone, replacing the default DND) will be
added later; the licensing code is present but bypassed.

## Requirements

- macOS 14.0 or later
- An Apple Silicon MacBook **with a lid-angle sensor** — not every model has
  one. The app checks on first launch and tells you plainly if yours doesn't.
  Confirmed models so far: MacBook Pro 16" (2019), MacBook Pro 14" (2021),
  MacBook Air (2022).
- Xcode 15+ / Swift 5.10+ to build

## Build

```sh
xcodebuild -scheme Ajar build
xcodebuild -scheme Ajar test
```

App Sandbox is **off** by design — the sandbox only allows IOKit through a
fixed entitlement list, and the lid sensor isn't on it. Hardened Runtime is
on. Settings live in `UserDefaults`; there is no database.

A signed, notarized DMG for people who don't want to build it themselves is
at <https://quietunit.com/ajar>.

## Why this repo is public

It's a portfolio piece and a compatibility reference. You can read it, build
it, run it, and fork it for your own use. You **cannot** sell it or use it
commercially — see [LICENSE](LICENSE) (PolyForm Noncommercial 1.0.0).

## Layout

- `Ajar/Sensor/` — `LidAngleReader`, the `IOHIDManager` wrapper
- `Ajar/Zones/` — zone engine, hysteresis, dwell, calibration
- `Ajar/Actions/` — mic mute, Shortcuts runner
- `Ajar/Lifecycle/` — sleep / clamshell / startup suppression
- `Ajar/Licensing/` — trial + license verification (present, bypassed in the free build)
- `Ajar/UI/` — menu bar, settings, onboarding
- `AjarTests/` — unit tests for the pure logic

Hardware layers (HID, CoreAudio, sleep/clamshell) are verified by hand, not
mocked.
