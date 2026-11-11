import AVFoundation
import Contacts
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
  case general, triggers, protection, bluetooth, notifications

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: return "General"
    case .triggers: return "Triggers"
    case .protection: return "Protection"
    case .bluetooth: return "Trusted Devices"
    case .notifications: return "Notifications"
    }
  }

  var icon: String {
    switch self {
    case .general: return "gear"
    case .triggers: return "bolt.fill"
    case .protection: return "shield.fill"
    case .bluetooth: return "antenna.radiowaves.left.and.right"
    case .notifications: return "bell.fill"
    }
  }
}

struct SettingsView: View {
  // General
  @State private var contactName: String = ""
  @State private var contactPhone: String = ""
  @State private var startAtLogin: Bool = false
  @State private var autoUpdateEnabled: Bool = true
  @State private var isCheckingForUpdates: Bool = false

  // Triggers
  @State private var triggerLidClose: Bool = true
  @State private var suppressLidTriggerWhenExternalDisplay: Bool = true
  @State private var triggerPowerDisconnect: Bool = true
  @State private var triggerPowerButton: Bool = false
  @State private var triggerMotionDetect: Bool = false
  @State private var motionSupported: Bool = true

  // Protection
  @State private var behaviorSleepPrevention: Bool = true
  @State private var behaviorLidCloseSleep: Bool = true
  @State private var behaviorShutdownBlocking: Bool = true
  @State private var behaviorLockScreen: Bool = true
  @State private var lockScreenOnTheftMode: Bool = false
  @State private var lockScreenOnShortcut: Bool = false
  @State private var lockScreenOnBluetoothArm: Bool = false
  @State private var lockScreenOnTelegramEnable: Bool = false
  @State private var biometricAuthEnabled: Bool = false
  @State private var behaviorAlarm: Bool = true
  @State private var behaviorAutoAlarm: Bool = false
  @State private var alarmVolume: Double = 100
  @State private var selectedAlarmSound: String = "Sosumi"
  @State private var offlineSirenEnabled: Bool = false

  // Bluetooth
  @State private var bluetoothAutoArmEnabled: Bool = false
  @State private var bluetoothArmGracePeriod: Double = 30
  @State private var trustedBLEDevices: [TrustedBLEDevice] = []
  @State private var trustedWiFiNetworks: [String] = []

  // Notifications
  @State private var telegramBotToken: String = ""
  @State private var telegramChatId: String = ""
  @State private var telegramEnabled: Bool = true
  @State private var notifyAutoArm: Bool = true
  @State private var notifyProtectionToggle: Bool = true
  @State private var trackLocation: Bool = true
  @State private var trackPublicIP: Bool = true
  @State private var trackWiFi: Bool = true
  @State private var trackBattery: Bool = true
  @State private var trackDeviceName: Bool = true
  @State private var photoCaptureEnabled: Bool = false
  @State private var verificationController: TelegramVerificationWindowController?

  @State private var isDaemonConnected = false
  @State private var daemonVersion: String?
  @State private var helperNeedsUpdate = false
  @State private var helperDisconnectedForUpdate = false
  @State private var helperAccessibilityGranted = false
  @State private var isInstallingHelper = false
  @State private var helperInstallResult: Bool?
  @State private var isCheckingForHelperUpdates = false
  @State private var selectedSection: SettingsSection? = .general
  @State private var showingResetConfirmation = false
  @State private var showCameraDenied = false
  @Environment(\.dismiss) private var dismiss

  private let alarmSounds = [
    "Siren",
    "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
    "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi",
    "Submarine", "Tink"
  ]

  private let settings = SettingsService.shared
  private let loginItem = LoginItemService.shared

  var body: some View {
    NavigationSplitView {
      List(selection: $selectedSection) {
        ForEach(SettingsSection.allCases) { section in
          Label(section.title, systemImage: section.icon)
            .tag(section)
        }
      }
      .listStyle(.sidebar)
      .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 200)
    } detail: {
      switch selectedSection {
      case .general:
        generalTab
      case .triggers:
        triggersTab
      case .protection:
        protectionTab
      case .bluetooth:
        bluetoothTab
      case .notifications:
        notificationsTab
      case nil:
        generalTab
      }
    }
    .frame(width: 600, height: 460)
    .onAppear {
      loadSettings()
      isDaemonConnected = TheftProtectionService.daemonConnected
      daemonVersion = TheftProtectionService.daemonVersion
      helperNeedsUpdate = TheftProtectionService.helperNeedsUpdate
      helperDisconnectedForUpdate = TheftProtectionService.helperDisconnectedForUpdate
      helperAccessibilityGranted = TheftProtectionService.helperAccessibilityGranted
      // Restored with the rest, not left at its optimistic `true` default. Only
      // the .helperStatusChanged handler wrote it, so opening Settings before
      // that round-trip landed showed the Motion toggle on hardware that cannot
      // do it: enabling it arms nothing (startMonitors and recalibrateMotion both
      // gate on daemonClient.motionSupported) while activeTriggerNames still
      // advertises "motion" in the arm message and every /status reply.
      motionSupported = TheftProtectionService.daemonMotionSupported
    }
    .onReceive(NotificationCenter.default.publisher(for: .daemonConnectionChanged)) { _ in
      isDaemonConnected = TheftProtectionService.daemonConnected
      daemonVersion = TheftProtectionService.daemonVersion
      helperNeedsUpdate = TheftProtectionService.helperNeedsUpdate
      helperDisconnectedForUpdate = TheftProtectionService.helperDisconnectedForUpdate
      helperAccessibilityGranted = TheftProtectionService.helperAccessibilityGranted
      if isDaemonConnected { helperInstallResult = nil }
    }
    .onReceive(NotificationCenter.default.publisher(for: .helperVersionChanged)) { _ in
      daemonVersion = TheftProtectionService.daemonVersion
      helperNeedsUpdate = TheftProtectionService.helperNeedsUpdate
    }
    .onReceive(NotificationCenter.default.publisher(for: .helperStatusChanged)) { _ in
      helperAccessibilityGranted = TheftProtectionService.helperAccessibilityGranted
      motionSupported = TheftProtectionService.daemonMotionSupported
    }
    .onReceive(NotificationCenter.default.publisher(for: .bluetoothSettingsChanged)) { _ in
      // AppDelegate's menu-bar item and the global shortcut mutate this setting
      // directly. Without re-reading it, the @State copy taken once in
      // loadSettings() goes stale and saveSettings() writes the stale value back
      // — silently reverting a toggle the user made while this window was open.
      // Worse when already .enabledBluetooth: the save also posts
      // .bluetoothSettingsChanged, whose handler stops the BLE service, so the
      // Mac stays armed with scanning dead and the trusted device returning can
      // never auto-disarm it.
      bluetoothAutoArmEnabled = settings.bluetoothAutoArmEnabled
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      NotificationCenter.default.post(name: .helperStatusRequested, object: nil)
    }
    .alert("Reset All Settings?", isPresented: $showingResetConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Reset", role: .destructive) {
        resetSettings()
      }
    } message: {
      Text("This will clear all stored credentials and preferences.")
    }
    .alert("Camera Access Required", isPresented: $showCameraDenied) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Camera permission is required to capture thief photos. Enable it in System Settings → Privacy & Security → Camera.")
    }
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        if #available(macOS 26.0, *) {
          Button("Cancel") {
            dismiss()
          }
          .buttonStyle(.glass)
        } else {
          Button("Cancel") {
            dismiss()
          }
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        if #available(macOS 26.0, *) {
          Button("Save") {
            saveSettings()
            dismiss()
          }
          .buttonStyle(.glassProminent)
        } else {
          Button("Save") {
            saveSettings()
            dismiss()
          }
        }
      }
    }
  }

  // MARK: - General Tab

  private var generalTab: some View {
    GeneralTabView(
      startAtLogin: $startAtLogin,
      biometricAuthEnabled: $biometricAuthEnabled,
      autoUpdateEnabled: $autoUpdateEnabled,
      showingResetConfirmation: $showingResetConfirmation,
      isCheckingForUpdates: isCheckingForUpdates,
      isInstallingHelper: isInstallingHelper,
      helperInstallResult: helperInstallResult,
      isDaemonConnected: isDaemonConnected,
      daemonVersion: daemonVersion,
      helperNeedsUpdate: helperNeedsUpdate,
      helperDisconnectedForUpdate: helperDisconnectedForUpdate,
      isCheckingForHelperUpdates: isCheckingForHelperUpdates,
      onToggleLoginItem: toggleLoginItem,
      onCheckForUpdates: checkForUpdates,
      onInstallHelper: installHelper,
      onCheckForHelperUpdates: checkForHelperUpdates
    )
  }

  // MARK: - Triggers Tab

  private var triggersTab: some View {
    TriggersTabView(
      triggerLidClose: $triggerLidClose,
      suppressLidTriggerWhenExternalDisplay: $suppressLidTriggerWhenExternalDisplay,
      triggerPowerDisconnect: $triggerPowerDisconnect,
      triggerPowerButton: $triggerPowerButton,
      triggerMotionDetect: $triggerMotionDetect,
      lockScreenOnShortcut: $lockScreenOnShortcut,
      isDaemonConnected: isDaemonConnected,
      helperAccessibilityGranted: helperAccessibilityGranted,
      motionSupported: motionSupported,
      onOpenAccessibility: openAccessibilitySettings
    )
  }

  // MARK: - Protection Tab

  private var protectionTab: some View {
    ProtectionTabView(
      behaviorSleepPrevention: $behaviorSleepPrevention,
      behaviorLidCloseSleep: $behaviorLidCloseSleep,
      behaviorShutdownBlocking: $behaviorShutdownBlocking,
      lockScreenOnTheftMode: $lockScreenOnTheftMode,
      behaviorLockScreen: $behaviorLockScreen,
      contactName: $contactName,
      contactPhone: $contactPhone,
      behaviorAutoAlarm: $behaviorAutoAlarm,
      selectedAlarmSound: $selectedAlarmSound,
      alarmVolume: $alarmVolume,
      offlineSirenEnabled: $offlineSirenEnabled,
      isDaemonConnected: isDaemonConnected,
      alarmSounds: alarmSounds,
      onLockScreenEnabled: onLockScreenEnabled,
      onRetrieveContacts: onRetrieveContacts
    )
  }

  // MARK: - Bluetooth Tab

  private var bluetoothTab: some View {
    BluetoothTabView(
      bluetoothAutoArmEnabled: $bluetoothAutoArmEnabled,
      bluetoothArmGracePeriod: $bluetoothArmGracePeriod,
      lockScreenOnBluetoothArm: $lockScreenOnBluetoothArm,
      trustedBLEDevices: $trustedBLEDevices,
      trustedWiFiNetworks: $trustedWiFiNetworks,
      isDaemonConnected: isDaemonConnected
    )
  }

  // MARK: - Notifications Tab

  private var notificationsTab: some View {
    NotificationsTabView(
      telegramEnabled: $telegramEnabled,
      telegramBotToken: $telegramBotToken,
      telegramChatId: $telegramChatId,
      lockScreenOnTelegramEnable: $lockScreenOnTelegramEnable,
      notifyAutoArm: $notifyAutoArm,
      notifyProtectionToggle: $notifyProtectionToggle,
      trackLocation: $trackLocation,
      trackPublicIP: $trackPublicIP,
      trackWiFi: $trackWiFi,
      trackBattery: $trackBattery,
      trackDeviceName: $trackDeviceName,
      photoCaptureEnabled: $photoCaptureEnabled,
      isDaemonConnected: isDaemonConnected,
      onConnect: { connectTelegram() },
      onPhotoCaptureEnabled: { primeCameraAccess() }
    )
  }

  // MARK: - Actions

  private func loadSettings() {
    contactName = settings.contactName ?? ""
    contactPhone = settings.contactPhone ?? ""
    telegramBotToken = settings.telegramBotToken ?? ""
    telegramChatId = settings.telegramChatId ?? ""
    telegramEnabled = settings.telegramEnabled
    startAtLogin = loginItem.isEnabled
    autoUpdateEnabled = settings.autoUpdateEnabled
    selectedAlarmSound = settings.alarmSound
    behaviorAutoAlarm = settings.behaviorAutoAlarm
    alarmVolume = Double(settings.alarmVolume)
    triggerLidClose = settings.triggerLidClose
    suppressLidTriggerWhenExternalDisplay = settings.suppressLidTriggerWhenExternalDisplay
    triggerPowerDisconnect = settings.triggerPowerDisconnect
    triggerPowerButton = settings.triggerPowerButton
    triggerMotionDetect = settings.triggerMotionDetect
    behaviorSleepPrevention = settings.behaviorSleepPrevention
    behaviorLidCloseSleep = settings.behaviorLidCloseSleep
    behaviorShutdownBlocking = settings.behaviorShutdownBlocking
    behaviorLockScreen = settings.behaviorLockScreen
    lockScreenOnTheftMode = settings.lockScreenOnTheftMode
    lockScreenOnShortcut = settings.lockScreenOnShortcut
    lockScreenOnBluetoothArm = settings.lockScreenOnBluetoothArm
    lockScreenOnTelegramEnable = settings.lockScreenOnTelegramEnable
    biometricAuthEnabled = settings.biometricAuthEnabled
    behaviorAlarm = settings.behaviorAlarm
    offlineSirenEnabled = settings.offlineSirenEnabled
    bluetoothAutoArmEnabled = settings.bluetoothAutoArmEnabled
    bluetoothArmGracePeriod = settings.bluetoothArmGracePeriod
    trustedBLEDevices = settings.trustedBLEDevices
    trustedWiFiNetworks = settings.trustedWiFiNetworks
    notifyAutoArm = settings.notifyAutoArm
    notifyProtectionToggle = settings.notifyProtectionToggle
    trackLocation = settings.trackLocation
    trackPublicIP = settings.trackPublicIP
    trackWiFi = settings.trackWiFi
    trackBattery = settings.trackBattery
    trackDeviceName = settings.trackDeviceName
    photoCaptureEnabled = settings.photoCaptureEnabled
  }

  private func saveSettings() {
    verificationController?.close()
    verificationController = nil
    settings.contactName = contactName.isEmpty ? nil : contactName
    settings.contactPhone = contactPhone.isEmpty ? nil : contactPhone
    let telegramChanged = settings.telegramBotToken != (telegramBotToken.isEmpty ? nil : telegramBotToken)
      || settings.telegramChatId != (telegramChatId.isEmpty ? nil : telegramChatId)
      || settings.telegramEnabled != telegramEnabled
    settings.telegramBotToken = telegramBotToken.isEmpty ? nil : telegramBotToken
    settings.telegramChatId = telegramChatId.isEmpty ? nil : telegramChatId
    settings.telegramEnabled = telegramEnabled
    if telegramChanged { NotificationCenter.default.post(name: .telegramSettingsChanged, object: nil) }
    settings.alarmSound = selectedAlarmSound
    settings.behaviorAutoAlarm = behaviorAutoAlarm
    settings.alarmVolume = Int(alarmVolume)
    settings.triggerLidClose = triggerLidClose
    settings.suppressLidTriggerWhenExternalDisplay = suppressLidTriggerWhenExternalDisplay
    settings.triggerPowerDisconnect = triggerPowerDisconnect
    settings.triggerPowerButton = triggerPowerButton
    settings.triggerMotionDetect = triggerMotionDetect
    NotificationCenter.default.post(name: .shortcutSettingsChanged, object: nil)
    settings.behaviorSleepPrevention = behaviorSleepPrevention
    settings.behaviorLidCloseSleep = behaviorLidCloseSleep
    settings.behaviorShutdownBlocking = behaviorShutdownBlocking
    settings.behaviorLockScreen = behaviorLockScreen
    settings.lockScreenOnTheftMode = lockScreenOnTheftMode
    settings.lockScreenOnShortcut = lockScreenOnShortcut
    settings.lockScreenOnBluetoothArm = lockScreenOnBluetoothArm
    settings.lockScreenOnTelegramEnable = lockScreenOnTelegramEnable
    settings.biometricAuthEnabled = biometricAuthEnabled
    settings.behaviorAlarm = behaviorAlarm
    settings.offlineSirenEnabled = offlineSirenEnabled

    settings.bluetoothAutoArmEnabled = bluetoothAutoArmEnabled
    settings.bluetoothArmGracePeriod = bluetoothArmGracePeriod
    settings.trustedBLEDevices = trustedBLEDevices
    settings.trustedWiFiNetworks = trustedWiFiNetworks
    NotificationCenter.default.post(name: .bluetoothSettingsChanged, object: nil)

    settings.notifyAutoArm = notifyAutoArm
    settings.notifyProtectionToggle = notifyProtectionToggle
    settings.trackLocation = trackLocation
    settings.trackPublicIP = trackPublicIP
    settings.trackWiFi = trackWiFi
    settings.trackBattery = trackBattery
    settings.trackDeviceName = trackDeviceName
    settings.photoCaptureEnabled = photoCaptureEnabled

    settings.autoUpdateEnabled = autoUpdateEnabled
    if autoUpdateEnabled {
      UpdateService.shared.startPeriodicChecks()
      HelperInstallService.shared.startPeriodicHelperChecks()
    } else {
      UpdateService.shared.stopPeriodicChecks()
      HelperInstallService.shared.stopPeriodicHelperChecks()
    }

    if !settings.setupComplete {
      settings.setupComplete = true
    }

    // Posted last, once every trigger/behavior value above is written.
    // startMonitors() latches these at arm time, so without this a change saved
    // while armed is advertised by activeTriggerNames()/activeBehaviorNames()
    // (which read live) but never actually started.
    NotificationCenter.default.post(name: .armedSettingsChanged, object: nil)

    ActivityLog.logAsync(.system, "Settings saved")
  }

  private func connectTelegram() {
    guard verificationController == nil else { return }
    let controller = TelegramVerificationWindowController()
    verificationController = controller
    controller.show(botToken: telegramBotToken) { chatId in
      self.verificationController = nil
      if let chatId = chatId { self.telegramChatId = chatId }
    }
  }

  private func resetSettings() {
    settings.resetAll()
    loadSettings()
    ActivityLog.logAsync(.system, "All settings reset")
  }

  private func openAccessibilitySettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
  }

  private func toggleLoginItem(_ enable: Bool) {
    if enable {
      _ = loginItem.enable()
    } else {
      _ = loginItem.disable()
    }
  }

  private var onLockScreenEnabled: (() -> Void)? { { requestContactsAndPopulate() } }
  private var onRetrieveContacts: (() -> Void)? { { retrieveFromContacts() } }

  private func checkForUpdates() {
    isCheckingForUpdates = true
    UpdateService.shared.checkForUpdates(silent: false) {
      DispatchQueue.main.async {
        isCheckingForUpdates = false
      }
    }
  }

  private func checkForHelperUpdates() {
    isCheckingForHelperUpdates = true
    HelperInstallService.shared.checkForHelperUpdates(silent: false) {
      DispatchQueue.main.async {
        isCheckingForHelperUpdates = false
      }
    }
  }

  private func installHelper() {
    isInstallingHelper = true
    helperInstallResult = nil
    HelperInstallService.shared.autoInstall { success in
      DispatchQueue.main.async {
        isInstallingHelper = false
        helperInstallResult = success
      }
    }
  }

  private func primeCameraAccess() {
    // Already authorized → nothing to prime. Also stops loadSettings()'s programmatic
    // toggle-restore from re-requesting (and false-alerting) every time settings open.
    guard CameraCaptureService.shared.authorizationStatus() != .authorized else { return }
    CameraCaptureService.shared.requestAccess { granted in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          if !granted {
            photoCaptureEnabled = false
            settings.photoCaptureEnabled = false
            showCameraDenied = true
          }
        }
      }
    }
  }

  private func requestContactsAndPopulate() {
    settings.requestContactsAccess { granted in
      if granted { DispatchQueue.main.async {
        if contactName.isEmpty { let n = NSFullUserName(); if !n.isEmpty { self.contactName = n } }
        if contactPhone.isEmpty, let p = contactsPhoneNumber() { self.contactPhone = p }
      } }
    }
  }

  private func retrieveFromContacts() {
    let name = NSFullUserName()
    if !name.isEmpty { contactName = name }
    settings.requestContactsAccess { granted in
      if granted { DispatchQueue.main.async { if let p = contactsPhoneNumber() { self.contactPhone = p } } }
    }
  }
}

private func contactsPhoneNumber() -> String? {
  let store = CNContactStore()
  guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return nil }
  let keys: [CNKeyDescriptor] = [CNContactPhoneNumbersKey as CNKeyDescriptor]
  guard let me = try? store.unifiedMeContactWithKeys(toFetch: keys) else { return nil }
  let mobile = me.phoneNumbers.first { $0.label == CNLabelPhoneNumberMobile }
  return mobile?.value.stringValue ?? me.phoneNumbers.first?.value.stringValue
}
