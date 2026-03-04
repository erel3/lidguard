# Corner Case Checker Memory

## Project: LidGuard
- macOS menu bar app, Swift 5.9, SPM, macOS 14.0+
- Theft protection via lid close / power disconnect / Bluetooth proximity
- GCD concurrency model with CFRunLoopPerformBlock for main thread dispatch
- Key queues: `com.lidguard.bluetooth`, `com.lidguard.tracking`, `com.lidguard.telegram.commands`

## Key Patterns
- Delegate callbacks dispatched to main via `CFRunLoopPerformBlock` + `CFRunLoopWakeUp`
- Exception: `TelegramCommandService` calls delegate directly on background queue (intentional, to avoid blocking when NSMenu is open)
- `ActivityLog.logAsync` is the only async/await usage (Task { @MainActor in })
- `SettingsService.shared` is thread-safe for reads (UserDefaults)
- `BluetoothProximityService` state is accessed exclusively on its private `queue`

## Known Issues Found (2026-03-02)
- State mutations in TheftProtectionService not synchronized (Telegram commands arrive on background queue)
- BluetoothDevicePickerView creates separate BluetoothProximityService instance (should share)
- notifyDelegate in BLE service captures delegate strongly before main thread dispatch
- BLE scan clears presence data each cycle (false positives with intermittent advertisers)
- enableProtectionBluetooth always locks screen regardless of setting
- shutdown() missing cleanup for several services

## File Structure
- `Sources/Services/BluetoothProximityService.swift` - BLE scanning, presence evaluation, grace timers
- `Sources/Views/BluetoothDevicePickerView.swift` - Device discovery UI
- `Sources/Services/TheftProtectionService.swift` - Main orchestrator, state machine
- `Sources/App/AppDelegate.swift` - Menu bar, UI state
