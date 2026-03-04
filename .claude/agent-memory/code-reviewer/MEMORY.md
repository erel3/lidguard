# Code Reviewer Memory

## Project: LidGuard (macOS menu bar app, Swift 5.9, SPM)

### Architecture
- Service-oriented with delegate-based communication
- GCD throughout (no async/await except ActivityLog)
- Main thread dispatch via `CFRunLoopPerformBlock` + `CFRunLoopWakeUp`
- Cross-queue logging via `ActivityLog.logAsync`
- Settings in `SettingsService` (UserDefaults) + `KeychainService` (secrets)

### Known Thread Safety Gaps
- `TheftProtectionService.state` is accessed from main thread AND Telegram command polling queue (background) without synchronization
- Delegate properties on services are set from main but read from background queues (weak var race)
- TelegramCommandService calls delegate directly on background queue (comment in code: "no main queue needed")

### Key Patterns to Verify
- New services should follow: private queue, delegate pattern, `notifyDelegate` via CFRunLoop
- Settings keys: `lidguard.*` prefix
- Logger categories must be added to: Logger extension, LogCategory enum, Config
- NotificationCenter used for settings change propagation (e.g., `.shortcutSettingsChanged`, `.bluetoothSettingsChanged`)
- Timer pattern: `DispatchSource.makeTimerSource(queue:)` with cancel/nil cleanup

### File Locations
- Services: `Sources/Services/`
- Views: `Sources/Views/`
- Config/Logger: `Sources/Config/Config.swift`
- AppDelegate: `Sources/App/AppDelegate.swift`
- Activity log model: `Sources/Services/ActivityLog.swift`
