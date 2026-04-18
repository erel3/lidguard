import CoreBluetooth
import Foundation
import os.log

struct TrustedBLEDevice: Codable, Identifiable, Equatable {
  let id: UUID
  var name: String
  var rssiThreshold: Int

  init(id: UUID, name: String, rssiThreshold: Int = Config.Bluetooth.defaultRssiThreshold) {
    self.id = id
    self.name = name
    self.rssiThreshold = rssiThreshold
  }
}

@MainActor
protocol BluetoothProximityDelegate: AnyObject {
  func bluetoothProximityAllDevicesLost(_ service: BluetoothProximityService)
  func bluetoothProximityDeviceReturned(_ service: BluetoothProximityService, device: TrustedBLEDevice)
}

@MainActor
final class BluetoothProximityService: NSObject {
  weak var delegate: BluetoothProximityDelegate?

  private var centralManager: CBCentralManager?

  private var isMonitoring = false
  private var isDiscoveryMode = false
  private var isPaused = false
  private var scanTimer: DispatchSourceTimer?

  private var seenThisCycle: Set<UUID> = []
  private var lastSeenRSSI: [UUID: Int] = [:]
  private var lastSeenTime: [UUID: Date] = [:]
  private var nearDevices: Set<UUID> = []
  private var allDevicesLostNotified = false
  private var btRecoveryUntil: Date?
  private var cachedTrustedDevices: [TrustedBLEDevice] = []
  private var cachedTrustedIDs: Set<UUID> = []
  private var cachedArmDelay: TimeInterval = Config.Bluetooth.defaultArmGracePeriod

  // Discovery mode: live RSSI for all peripherals
  private var discoveredDevices: [UUID: (name: String, rssi: Int)] = [:]
  var onDiscoveryUpdate: (([UUID: (name: String, rssi: Int)]) -> Void)?

  override init() {
    super.init()
  }

  // MARK: - Monitoring

  func start() {
    guard !isMonitoring else { return }
    let devices = SettingsService.shared.trustedBLEDevices
    guard !devices.isEmpty else {
      Logger.bluetooth.info("No trusted devices configured, skipping BLE monitoring")
      return
    }
    cachedTrustedDevices = devices
    cachedTrustedIDs = Set(devices.map(\.id))
    cachedArmDelay = max(60.0, SettingsService.shared.bluetoothArmGracePeriod)
    btRecoveryUntil = Date().addingTimeInterval(cachedArmDelay)
    isMonitoring = true
    if centralManager == nil {
      centralManager = CBCentralManager(delegate: self, queue: .main)
    } else if centralManager?.state == .poweredOn {
      startScanCycle()
    }
    Logger.bluetooth.info("Bluetooth proximity monitoring started")
    ActivityLog.logAsync(.bluetooth, "Proximity monitoring started")
  }

  /// Returns (deviceName, rssi or nil if absent) for each trusted device.
  func getDeviceStatus(completion: @escaping @Sendable ([(name: String, rssi: Int?)]) -> Void) {
    let now = Date()
    let result = cachedTrustedDevices.map { device -> (name: String, rssi: Int?) in
      let isPresent: Bool
      if let seen = lastSeenTime[device.id] {
        isPresent = now.timeIntervalSince(seen) < cachedArmDelay
      } else {
        isPresent = false
      }
      let rssi = isPresent ? lastSeenRSSI[device.id] : nil
      return (name: device.name, rssi: rssi)
    }
    completion(result)
  }

  func stop() {
    guard isMonitoring else { return }
    isMonitoring = false
    isPaused = false
    stopScanCycle()
    seenThisCycle.removeAll()
    lastSeenRSSI.removeAll()
    lastSeenTime.removeAll()
    nearDevices.removeAll()
    allDevicesLostNotified = false
    btRecoveryUntil = nil
    if !isDiscoveryMode {
      centralManager = nil
    }
    Logger.bluetooth.info("Bluetooth proximity monitoring stopped")
    ActivityLog.logAsync(.bluetooth, "Proximity monitoring stopped")
  }

  func restart() {
    isPaused = false
    if isMonitoring {
      isMonitoring = false
      stopScanCycle()
      seenThisCycle.removeAll()
      lastSeenRSSI.removeAll()
      lastSeenTime.removeAll()
      nearDevices.removeAll()
      allDevicesLostNotified = false
      btRecoveryUntil = nil
    }
    let devices = SettingsService.shared.trustedBLEDevices
    guard !devices.isEmpty else {
      Logger.bluetooth.info("No trusted devices configured, skipping BLE monitoring")
      if !isDiscoveryMode { centralManager = nil }
      return
    }
    cachedTrustedDevices = devices
    cachedTrustedIDs = Set(devices.map(\.id))
    cachedArmDelay = max(60.0, SettingsService.shared.bluetoothArmGracePeriod)
    btRecoveryUntil = Date().addingTimeInterval(cachedArmDelay)
    isMonitoring = true
    if centralManager == nil {
      centralManager = CBCentralManager(delegate: self, queue: .main)
    } else if centralManager?.state == .poweredOn {
      startScanCycle()
    }
    Logger.bluetooth.info("Bluetooth proximity monitoring restarted")
  }

  // MARK: - Discovery Mode (for Settings UI)

  func startDiscovery() {
    isDiscoveryMode = true
    discoveredDevices.removeAll()
    if centralManager == nil {
      centralManager = CBCentralManager(delegate: self, queue: .main)
    } else if centralManager?.state == .poweredOn {
      centralManager?.scanForPeripherals(
        withServices: nil,
        options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
      )
    }
  }

  func stopDiscovery() {
    isDiscoveryMode = false
    if !isMonitoring {
      centralManager?.stopScan()
      centralManager = nil
    }
    discoveredDevices.removeAll()
    onDiscoveryUpdate = nil
  }

  // MARK: - Sleep/Wake

  func pause() {
    guard isMonitoring else { return }
    isPaused = true
    stopScanCycle()
    Logger.bluetooth.info("BLE scanning paused for sleep")
  }

  func resume() {
    guard isPaused else { return }
    isPaused = false
    scanTimer?.cancel()
    scanTimer = nil
    guard isMonitoring, centralManager?.state == .poweredOn else { return }
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 2.0)
    timer.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        self?.startScanCycle()
      }
    }
    timer.resume()
    scanTimer = timer
    Logger.bluetooth.info("BLE scanning will resume after wake delay")
  }

  // MARK: - Scan Cycle (called on queue)

  private func startScanCycle() {
    guard isMonitoring, centralManager?.state == .poweredOn else { return }
    scanBurst()
  }

  private var scanPause: TimeInterval {
    let cycle = cachedArmDelay / 4.0
    return min(60, max(15, cycle - Config.Bluetooth.scanDuration))
  }

  private func scanBurst() {
    guard isMonitoring, centralManager?.state == .poweredOn else { return }

    seenThisCycle.removeAll()

    let allowDuplicates = isDiscoveryMode
    centralManager?.scanForPeripherals(
      withServices: nil,
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates]
    )

    scanTimer?.cancel()
    scanTimer = DispatchSource.makeTimerSource(queue: .main)
    scanTimer?.schedule(deadline: .now() + Config.Bluetooth.scanDuration)
    scanTimer?.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        self?.endScanBurst()
      }
    }
    scanTimer?.resume()
  }

  private func endScanBurst() {
    guard isMonitoring else { return }

    if !isDiscoveryMode {
      centralManager?.stopScan()
    }

    // Update lastSeenTime for devices detected this cycle
    let now = Date()
    for deviceID in seenThisCycle where cachedTrustedIDs.contains(deviceID) {
      lastSeenTime[deviceID] = now
    }

    evaluatePresence()

    scanTimer?.cancel()
    scanTimer = DispatchSource.makeTimerSource(queue: .main)
    scanTimer?.schedule(deadline: .now() + scanPause)
    scanTimer?.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        self?.scanBurst()
      }
    }
    scanTimer?.resume()
  }

  private func stopScanCycle() {
    scanTimer?.cancel()
    scanTimer = nil
    centralManager?.stopScan()
  }

  // MARK: - Presence Evaluation (called on queue)

  private func checkRecoveryCooldown() -> Bool {
    guard let recoveryUntil = btRecoveryUntil else { return false }
    if Date() < recoveryUntil {
      Logger.bluetooth.debug("Skipping presence evaluation — BT recovery cooldown active")
      return true
    }
    Logger.bluetooth.debug("BT recovery cooldown expired, resuming evaluation")
    btRecoveryUntil = nil
    return false
  }

  private func computeNearDevices(at now: Date) -> Set<UUID> {
    var currentNear = Set<UUID>()
    for device in cachedTrustedDevices {
      guard let seen = lastSeenTime[device.id],
            now.timeIntervalSince(seen) < cachedArmDelay,
            let rssi = lastSeenRSSI[device.id] else { continue }

      let wasNear = nearDevices.contains(device.id)
      let threshold = wasNear
        ? device.rssiThreshold - Config.Bluetooth.rssiHysteresis
        : device.rssiThreshold + Config.Bluetooth.rssiHysteresis

      if rssi >= threshold {
        currentNear.insert(device.id)
      }
    }
    return currentNear
  }

  private func evaluatePresence() {
    guard isMonitoring, !isPaused, !cachedTrustedDevices.isEmpty else { return }
    guard !checkRecoveryCooldown() else { return }

    let now = Date()
    let previousNear = nearDevices
    let currentNear = computeNearDevices(at: now)
    nearDevices = currentNear

    if currentNear.isEmpty {
      handleAllDevicesLost(previousNear: previousNear, now: now)
    } else if allDevicesLostNotified || previousNear.isEmpty {
      handleDeviceReturned(currentNear: currentNear)
    }
  }

  private func handleAllDevicesLost(previousNear: Set<UUID>, now: Date) {
    guard !allDevicesLostNotified else { return }
    let armDelay = cachedArmDelay
    let seenTimes = lastSeenTime
    let allGone = cachedTrustedDevices.allSatisfy { device in
      guard let seen = seenTimes[device.id] else { return true }
      return now.timeIntervalSince(seen) >= armDelay
    }
    guard allGone else {
      if !previousNear.isEmpty {
        Logger.bluetooth.info("All trusted devices out of range, waiting for arm delay")
        ActivityLog.logAsync(.bluetooth, "All trusted devices out of range, waiting \(Int(armDelay))s")
      }
      return
    }
    allDevicesLostNotified = true
    Logger.bluetooth.info("All trusted devices gone for \(Int(armDelay))s, triggering auto-arm")
    ActivityLog.logAsync(.bluetooth, "All devices out of range for \(Int(armDelay))s — auto-arming")
    notifyDelegate { $0.bluetoothProximityAllDevicesLost(self) }
  }

  private func handleDeviceReturned(currentNear: Set<UUID>) {
    guard let device = cachedTrustedDevices.first(where: { currentNear.contains($0.id) }) else { return }
    Logger.bluetooth.info("Trusted device returned: \(device.name)")
    ActivityLog.logAsync(.bluetooth, "Device returned: \(device.name)")
    allDevicesLostNotified = false
    notifyDelegate { $0.bluetoothProximityDeviceReturned(self, device: device) }
  }

  // MARK: - Delegate Dispatch

  private func notifyDelegate(_ block: (BluetoothProximityDelegate) -> Void) {
    guard let delegate else { return }
    block(delegate)
  }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothProximityService: @preconcurrency CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
    case .poweredOn:
      Logger.bluetooth.info("Bluetooth powered on")
      if isMonitoring && !isPaused {
        btRecoveryUntil = Date().addingTimeInterval(Config.Bluetooth.btRecoveryCooldown)
        startScanCycle()
      }
      if isDiscoveryMode && !isPaused {
        central.scanForPeripherals(
          withServices: nil,
          options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
      }
    case .poweredOff:
      Logger.bluetooth.warning("Bluetooth powered off — treating as all devices lost")
      ActivityLog.logAsync(.bluetooth, "Bluetooth off — all devices considered gone")
      btRecoveryUntil = nil
      stopScanCycle()
      // Schedule evaluation after arm delay so auto-arm fires even with BT off
      if isMonitoring && !allDevicesLostNotified {
        let delay = cachedArmDelay
        scanTimer = DispatchSource.makeTimerSource(queue: .main)
        scanTimer?.schedule(deadline: .now() + delay)
        scanTimer?.setEventHandler { [weak self] in
          MainActor.assumeIsolated {
            self?.evaluatePresence()
          }
        }
        scanTimer?.resume()
      }
    default:
      Logger.bluetooth.info("Bluetooth state: \(String(describing: central.state.rawValue))")
    }
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    let rssiValue = RSSI.intValue
    guard rssiValue < 0 else { return } // Filter unavailable (127) and invalid (0, positive)

    // Discovery mode: track all named peripherals
    if isDiscoveryMode {
      let name = peripheral.name
        ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
      if let name = name, !name.isEmpty {
        discoveredDevices[peripheral.identifier] = (name: name, rssi: rssiValue)
        onDiscoveryUpdate?(discoveredDevices)
      }
    }

    // Monitoring mode: track trusted devices
    if isMonitoring {
      if cachedTrustedIDs.contains(peripheral.identifier) {
        seenThisCycle.insert(peripheral.identifier)
        lastSeenRSSI[peripheral.identifier] = rssiValue
      }
    }
  }
}
