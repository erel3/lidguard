# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LidGuard is a macOS menu bar application for laptop theft protection. Detects lid close and power disconnect events, then sends device tracking (location, IP, WiFi, battery) to Telegram and Pushover.

**Swift 5.9 / macOS 14.0+ / SPM** — Not sandboxed (requires IOKit, sudo, Accessibility).

## Build Commands

```bash
make build               # Swift release build only (no .app bundle)
make run                 # Bundle with -dev suffix and open (main dev workflow)
make run-debug           # Build debug binary and run directly (fast, no bundle)
make install             # Copy current dist/.app to /Applications
make release             # Bump version, build, notarize, commit, tag, push, gh release
make clean               # Remove .build and dist
make icon                # Regenerate AppIcon.icns from Scripts/generate_icon.swift
BUMP=minor make release  # Bump minor instead of patch (also: major)
```

## Release Workflow

`make release` does everything: bump version → build → bundle → notarize → commit → tag → zip → push → `gh release create`.

- **Title**: defaults to `vX.Y.Z`, override with `TITLE="..." make release`
- **Notes**: `RELEASE_NOTES.md` is **required** — release fails without it. Create a fresh one before each release; it is deleted automatically after publish.
- **Version bump**: `BUMP=patch` (default), `BUMP=minor`, `BUMP=major`
- **Notarization**: Uses `xcrun notarytool` with keychain profile `Notarize`, then `xcrun stapler staple`.

GitHub repo: `Erel3/lidguard`. Requires `gh` CLI authenticated.

## Architecture

**Service-oriented design** with delegate-based communication. All services in `Sources/Services/`.

### State Machine

`TheftProtectionService` manages three states via `ProtectionState`:
- `disabled` → `enabled` (user arms protection)
- `enabled` → `theftMode` (lid close or power disconnect triggers)
- `theftMode` → `enabled` (owner authenticates via Touch ID or Telegram `/stop` or `/safe`)

Protection state is NOT persisted — always starts `disabled` on launch. `disableProtection` only works from `.enabled` state (must deactivate theft mode first).

### Core Services

- **TheftProtectionService** — Main orchestrator. Manages state transitions, coordinates all services. Sends tracking updates every 20s in theft mode. Exposes `TheftProtectionDelegate` (state changes, shortcut triggers). Implements `LidMonitorDelegate`, `TelegramCommandDelegate`, `SleepWakeDelegate`, `PowerMonitorDelegate`, `PowerButtonDelegate`, `GlobalShortcutDelegate`. Uses `NotificationService` protocol (not `TelegramService` directly). `enableProtection` has optional `lockScreen:` parameter.
- **LidMonitorService** — Polls IOKit `AppleClamshellState` every 0.5s.
- **PowerMonitorService** — Monitors AC power via IOPSNotification.
- **PowerButtonMonitor** — NSEvent global monitor for power button press. Sends alert but does NOT activate theft mode. Requires Accessibility.
- **GlobalShortcutService** — System-wide hotkey via NSEvent global monitor. Toggles protection on/off. Configurable in settings, requires Accessibility.
- **TelegramService/TelegramCommandService** — `TelegramService` conforms to `NotificationService` protocol (`send(message:keyboard:completion:)`). Sends messages with reply keyboards (5 `TelegramKeyboard` cases: `.none`, `.theftMode`, `.theftModeAlarmOn`, `.enabled`, `.disabled`). Alarm buttons conditional on `behaviorAlarm` setting. Command service polls every 3s for remote commands: `/stop`, `/safe`, `/status`, `/enable`, `/disable`, `/alarm`, `/stopalarm`.
- **DeviceInfoCollector** — Aggregates LocationService, SystemInfoService into DeviceInfo model.

### Supporting Services

- **SleepPreventionService** — IOPMAssertion to prevent both idle and system sleep
- **PmsetService** — Runs `pmset disablesleep` with admin privileges via `/etc/sudoers.d/lidguard`
- **SleepWakeService** — IOKit callbacks for sleep/wake events; can deny sleep in theft mode
- **AlarmAudioManager** — Singleton. Synthesized siren via `AVAudioEngine` + `AVAudioSourceNode` (500–1400 Hz sweep, harmonics, soft clipping). Manages system volume via CoreAudio (saves/restores, enforces max during alarm with property listener on `com.lidguard.volumemonitor` queue). Persists saved volume to UserDefaults for crash recovery (`restoreSystemVolumeIfNeeded` on init). `previewSiren()` plays 1.5s preview without volume enforcement for Settings.
- **LockScreenMessageService** — Uses SkyLight private API for fullscreen overlay window. Contains embedded `LockScreenMessageView` (SwiftUI) and `LockScreenViewModel`. Displays owner contact info from settings.
- **UpdateService** — Singleton. Checks GitHub Releases API for new versions. Auto-checks on launch + every 2 days (configurable). Shows modal update window with changelog. Downloads zip, verifies codesign, atomically replaces `.app` bundle via `FileManager.replaceItem`, restarts via detached shell process. Supports skip version. Uses `com.lidguard.update` queue.
- **LoginItemService** — Launch-at-login via `SMAppService`.
- **BiometricAuthService** — Touch ID for sensitive menu actions (settings, disable, quit)
- **PushoverService** — Fast push notifications with priority=1 and siren sound
- **NetworkRetry** — HTTP retry utility (3 attempts, 2s delay)
- **ActivityLog** — `@MainActor` class. In-memory (500 entries max) + JSON disk persistence at `~/Library/Application Support/LidGuard/activity-log.json`. 9 categories: `.system`, `.armed`, `.disarmed`, `.trigger`, `.theft`, `.telegram`, `.pushover`, `.power`, `.location`. Uses `Task { @MainActor in }` for cross-queue dispatch (only async/await usage in codebase).
- **SettingsService/KeychainService** — UserDefaults for prefs, macOS Keychain for secrets (telegram.botToken, telegram.chatId, pushover.userKey, pushover.apiToken). Auto-populates contact phone from Contacts Me card.

### Key Settings

- `autoUpdateEnabled` — auto-check for updates on launch + every 2 days (default true)
- `skippedVersion` — version the user chose to skip
- `behaviorAutoAlarm` — auto-play alarm on theft mode activation
- `alarmVolume` — alarm volume (10–100 in steps of 10)
- `contactName` / `contactPhone` — owner info shown on lock screen overlay
- `shortcutEnabled` — global shortcut on/off toggle
- `pushoverEnabled` / `telegramEnabled` — per-service enable toggles

### Key Files

- `Sources/App/AppDelegate.swift` — Menu bar UI with custom CoreGraphics-drawn laptop+eye icons (`.eyeOpen` green, `.eyeClosed` template, `.eyeAlert` red). Right-click quick toggle. Option key reveals hidden menu items (test alert, activity log). Dock icon toggles `.accessory`/`.regular` by protection state. Shutdown blocking via `applicationShouldTerminate`.
- `Sources/Config/Config.swift` — Credentials loaded from SettingsService/KeychainService, Logger extensions
- `Sources/Views/SettingsView.swift` — SwiftUI settings panel
- `Sources/Views/SettingsWindowController.swift` — NSWindow wrapper for SettingsView
- `Sources/Views/ActivityLogView.swift` — SwiftUI view with search/filter for activity log
- `Sources/Views/ActivityLogWindowController.swift` — NSWindow wrapper for ActivityLogView
- `Sources/Views/UpdateView.swift` — SwiftUI modal for update prompt (changelog, install/skip/dismiss)
- `Sources/Views/ShortcutRecorderView.swift` — NSViewRepresentable for recording global keyboard shortcuts

## Concurrency

GCD throughout with one exception. Key background queues:
- `com.lidguard.lidmonitor` (userInitiated) — lid polling every 0.5s
- `com.lidguard.tracking` (userInitiated) — tracking updates every 20s
- `com.lidguard.telegram.commands` (utility) — command polling every 3s
- `com.lidguard.volumemonitor` — CoreAudio volume enforcement during alarm

Cross-queue callbacks use `CFRunLoopPerformBlock` + `CFRunLoopWakeUp` to avoid blocking the main thread. `ActivityLog` is the sole exception using `Task { @MainActor in }`.

## Dependencies

- **SkyLightWindow** (SPM, v1.0.0+) — Private API wrapper for fullscreen overlay windows
- **Apple frameworks**: IOKit, CoreLocation, CoreWLAN, LocalAuthentication, AppKit, AVFoundation, CoreAudio, Contacts, ServiceManagement, Security, ApplicationServices
