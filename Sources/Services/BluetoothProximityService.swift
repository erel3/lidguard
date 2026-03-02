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

protocol BluetoothProximityDelegate: AnyObject {
  func bluetoothProximityAllDevicesLost(_ service: BluetoothProximityService)
  func bluetoothProximityDeviceReturned(_ service: BluetoothProximityService, device: TrustedBLEDevice)
}

final class BluetoothProximityService: NSObject {
  weak var delegate: BluetoothProximityDelegate?

  private var centralManager: CBCentralManager?
  private let queue = DispatchQueue(label: "com.lidguard.bluetooth", qos: .utility)

  // All mutable state below is accessed exclusively on `queue`
  private var isMonitoring = false
  private var isDiscoveryMode = false
  private var scanTimer: DispatchSourceTimer?
  private var armGraceTimer: DispatchSourceTimer?
  private var disarmGraceTimer: DispatchSourceTimer?

  private var presentDevices: Set<UUID> = []
  private var lastSeenRSSI: [UUID: Int] = [:]
  private var cachedTrustedDevices: [TrustedBLEDevice] = []
  private var cachedTrustedIDs: Set<UUID> = []

  // Discovery mode: live RSSI for all peripherals
  private var discoveredDevices: [UUID: (name: String, rssi: Int)] = [:]
  var onDiscoveryUpdate: (([UUID: (name: String, rssi: Int)]) -> Void)?

  override init() {
    super.init()
  }

  private func refreshTrustedDevicesCache() {
    // Called on queue
    cachedTrustedDevices = SettingsService.shared.trustedBLEDevices
    cachedTrustedIDs = Set(cachedTrustedDevices.map(\.id))
  }

  // MARK: - Monitoring

  func start() {
    queue.async { [self] in
      guard !isMonitoring else { return }
      let devices = SettingsService.shared.trustedBLEDevices
      guard !devices.isEmpty else {
        Logger.bluetooth.info("No trusted devices configured, skipping BLE monitoring")
        return
      }
      cachedTrustedDevices = devices
      cachedTrustedIDs = Set(devices.map(\.id))
      isMonitoring = true
      if centralManager == nil {
        centralManager = CBCentralManager(delegate: self, queue: queue)
      } else if centralManager?.state == .poweredOn {
        startScanCycle()
      }
      Logger.bluetooth.info("Bluetooth proximity monitoring started")
      ActivityLog.logAsync(.bluetooth, "Proximity monitoring started")
    }
  }

  /// Returns (deviceName, rssi or nil if absent) for each trusted device. Thread-safe.
  func getDeviceStatus(completion: @escaping ([(name: String, rssi: Int?)]) -> Void) {
    queue.async { [self] in
      let result = cachedTrustedDevices.map { device -> (name: String, rssi: Int?) in
        let rssi = presentDevices.contains(device.id) ? lastSeenRSSI[device.id] : nil
        return (name: device.name, rssi: rssi)
      }
      completion(result)
    }
  }

  func stop() {
    queue.async { [self] in
      guard isMonitoring else { return }
      isMonitoring = false
      stopScanCycle()
      cancelArmGrace()
      cancelDisarmGrace()
      presentDevices.removeAll()
      lastSeenRSSI.removeAll()
      if !isDiscoveryMode {
        centralManager = nil
      }
      Logger.bluetooth.info("Bluetooth proximity monitoring stopped")
      ActivityLog.logAsync(.bluetooth, "Proximity monitoring stopped")
    }
  }

  func restart() {
    queue.async { [self] in
      // Inline stop
      if isMonitoring {
        isMonitoring = false
        stopScanCycle()
        cancelArmGrace()
        cancelDisarmGrace()
        presentDevices.removeAll()
        lastSeenRSSI.removeAll()
      }
      // Inline start
      let devices = SettingsService.shared.trustedBLEDevices
      guard !devices.isEmpty else {
        Logger.bluetooth.info("No trusted devices configured, skipping BLE monitoring")
        if !isDiscoveryMode { centralManager = nil }
        return
      }
      cachedTrustedDevices = devices
      cachedTrustedIDs = Set(devices.map(\.id))
      isMonitoring = true
      if centralManager == nil {
        centralManager = CBCentralManager(delegate: self, queue: queue)
      } else if centralManager?.state == .poweredOn {
        startScanCycle()
      }
      Logger.bluetooth.info("Bluetooth proximity monitoring restarted")
    }
  }

  // MARK: - Discovery Mode (for Settings UI)

  func startDiscovery() {
    queue.async { [self] in
      isDiscoveryMode = true
      discoveredDevices.removeAll()
      if centralManager == nil {
        centralManager = CBCentralManager(delegate: self, queue: queue)
      } else if centralManager?.state == .poweredOn {
        centralManager?.scanForPeripherals(
          withServices: nil,
          options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
      }
    }
  }

  func stopDiscovery() {
    queue.async { [self] in
      isDiscoveryMode = false
      if !isMonitoring {
        centralManager?.stopScan()
        centralManager = nil
      }
      discoveredDevices.removeAll()
      DispatchQueue.main.async { [weak self] in
        self?.onDiscoveryUpdate = nil
      }
    }
  }

  // MARK: - Scan Cycle (called on queue)

  private func startScanCycle() {
    guard isMonitoring, centralManager?.state == .poweredOn else { return }
    scanBurst()
  }

  private func scanBurst() {
    guard isMonitoring, centralManager?.state == .poweredOn else { return }

    presentDevices.removeAll()
    lastSeenRSSI.removeAll()

    let allowDuplicates = isDiscoveryMode
    centralManager?.scanForPeripherals(
      withServices: nil,
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates]
    )

    scanTimer?.cancel()
    scanTimer = DispatchSource.makeTimerSource(queue: queue)
    scanTimer?.schedule(deadline: .now() + Config.Bluetooth.scanDuration)
    scanTimer?.setEventHandler { [weak self] in
      self?.endScanBurst()
    }
    scanTimer?.resume()
  }

  private func endScanBurst() {
    guard isMonitoring else { return }

    if !isDiscoveryMode {
      centralManager?.stopScan()
    }

    evaluatePresence()

    scanTimer?.cancel()
    scanTimer = DispatchSource.makeTimerSource(queue: queue)
    scanTimer?.schedule(deadline: .now() + Config.Bluetooth.scanPause)
    scanTimer?.setEventHandler { [weak self] in
      self?.scanBurst()
    }
    scanTimer?.resume()
  }

  private func stopScanCycle() {
    scanTimer?.cancel()
    scanTimer = nil
    centralManager?.stopScan()
  }

  // MARK: - Presence Evaluation (called on queue)

  private func evaluatePresence() {
    let trusted = cachedTrustedDevices
    guard !trusted.isEmpty else { return }

    let presentTrusted = trusted.filter { device in
      guard presentDevices.contains(device.id) else { return false }
      guard let rssi = lastSeenRSSI[device.id] else { return false }
      return rssi >= device.rssiThreshold
    }

    if presentTrusted.isEmpty {
      if armGraceTimer == nil {
        Logger.bluetooth.info("All trusted devices lost, starting arm grace period")
        ActivityLog.logAsync(.bluetooth, "All trusted devices out of range, grace period started")
        startArmGrace()
      }
      cancelDisarmGrace()
    } else {
      cancelArmGrace()
      if disarmGraceTimer == nil {
        let device = presentTrusted[0]
        Logger.bluetooth.info("Trusted device returned: \(device.name)")
        ActivityLog.logAsync(.bluetooth, "Device returned: \(device.name)")
        startDisarmGrace(device: device)
      }
    }
  }

  // MARK: - Grace Periods (called on queue)

  private func startArmGrace() {
    cancelArmGrace()
    let gracePeriod = max(1.0, SettingsService.shared.bluetoothArmGracePeriod)
    armGraceTimer = DispatchSource.makeTimerSource(queue: queue)
    armGraceTimer?.schedule(deadline: .now() + gracePeriod)
    armGraceTimer?.setEventHandler { [weak self] in
      guard let self = self else { return }
      self.armGraceTimer = nil
      Logger.bluetooth.info("Arm grace period expired, triggering auto-arm")
      ActivityLog.logAsync(.bluetooth, "Grace period expired — auto-arming protection")
      self.notifyDelegate { $0.bluetoothProximityAllDevicesLost(self) }
    }
    armGraceTimer?.resume()
  }

  private func cancelArmGrace() {
    armGraceTimer?.cancel()
    armGraceTimer = nil
  }

  private func startDisarmGrace(device: TrustedBLEDevice) {
    cancelDisarmGrace()
    let gracePeriod = max(0.0, SettingsService.shared.bluetoothDisarmGracePeriod)
    disarmGraceTimer = DispatchSource.makeTimerSource(queue: queue)
    disarmGraceTimer?.schedule(deadline: .now() + gracePeriod)
    disarmGraceTimer?.setEventHandler { [weak self] in
      guard let self = self else { return }
      self.disarmGraceTimer = nil
      Logger.bluetooth.info("Disarm grace period expired, triggering auto-disarm")
      ActivityLog.logAsync(.bluetooth, "Device confirmed back — auto-disarming protection")
      self.notifyDelegate { $0.bluetoothProximityDeviceReturned(self, device: device) }
    }
    disarmGraceTimer?.resume()
  }

  private func cancelDisarmGrace() {
    disarmGraceTimer?.cancel()
    disarmGraceTimer = nil
  }

  // MARK: - Delegate Dispatch

  private func notifyDelegate(_ block: @escaping (BluetoothProximityDelegate) -> Void) {
    guard let delegate = delegate else { return }
    CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
      block(delegate)
    }
    CFRunLoopWakeUp(CFRunLoopGetMain())
  }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothProximityService: CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
    case .poweredOn:
      Logger.bluetooth.info("Bluetooth powered on")
      if isMonitoring {
        startScanCycle()
      }
      if isDiscoveryMode {
        central.scanForPeripherals(
          withServices: nil,
          options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
      }
    case .poweredOff:
      Logger.bluetooth.warning("Bluetooth powered off — treating as all devices lost")
      ActivityLog.logAsync(.bluetooth, "Bluetooth off — all devices considered gone")
      stopScanCycle()
      cancelDisarmGrace()
      // Bluetooth off = can't see any devices = all lost → start arm grace
      if isMonitoring && armGraceTimer == nil {
        startArmGrace()
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
        DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }
          self.onDiscoveryUpdate?(self.discoveredDevices)
        }
      }
    }

    // Monitoring mode: track trusted devices
    if isMonitoring {
      if cachedTrustedIDs.contains(peripheral.identifier) {
        presentDevices.insert(peripheral.identifier)
        lastSeenRSSI[peripheral.identifier] = rssiValue
      }
    }
  }
}
