#if !APPSTORE
import Contacts
#endif
import KeyboardShortcuts
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
  case general, triggers, protection, bluetooth, notifications

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: return "General"
    case .triggers: return "Triggers"
    case .protection: return "Protection"
    case .bluetooth: return "Bluetooth"
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
  #if !APPSTORE
  @State private var autoUpdateEnabled: Bool = true
  @State private var isCheckingForUpdates: Bool = false
  #endif

  // Triggers
  @State private var triggerLidClose: Bool = true
  @State private var triggerPowerDisconnect: Bool = true
  @State private var triggerPowerButton: Bool = false

  // Global Shortcut
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
    Form {
      Section {
        Toggle("Start at Login", isOn: $startAtLogin)
          .onChange(of: startAtLogin) { _, newValue in
            toggleLoginItem(newValue)
          }
      } header: {
        Text("Launch")
      }

      Section {
        Toggle("Require Touch ID", isOn: $biometricAuthEnabled)
      } header: {
        Text("Security")
      } footer: {
        Text("Require Touch ID or password to disable protection, open settings, and quit.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      #if !APPSTORE
      Section {
        Toggle("Automatically check for updates", isOn: $autoUpdateEnabled)
        HStack {
          Spacer()
          if #available(macOS 26.0, *) {
            Button(isCheckingForUpdates ? "Checking..." : "Check for Updates") {
              checkForUpdates()
            }
            .buttonStyle(.glass)
            .disabled(isCheckingForUpdates)
          } else {
            Button(isCheckingForUpdates ? "Checking..." : "Check for Updates") {
              checkForUpdates()
            }
            .buttonStyle(.borderless)
            .disabled(isCheckingForUpdates)
          }
          Spacer()
        }
      } header: {
        Text("Updates")
      }
      #endif

      Section {
        HStack {
          if isInstallingHelper {
            ProgressView()
              .controlSize(.small)
            Text("Installing Helper...")
          } else if helperInstallResult == true {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
            Text("Helper Installed Successfully")
          } else if helperInstallResult == false {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.red)
            Text("Helper Install Failed")
          } else if helperNeedsUpdate {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
            Text("Helper Outdated (v\(daemonVersion ?? "?"), requires v\(Config.Daemon.minHelperVersion))")
          } else if isDaemonConnected {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
            Text("Helper Connected (v\(daemonVersion ?? "?"))")
          } else if helperDisconnectedForUpdate {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.orange)
            Text("Disconnected — helper too old (requires v\(Config.Daemon.minHelperVersion))")
          } else {
            Image(systemName: "xmark.circle")
              .foregroundStyle(.secondary)
            Text("Helper Not Connected")
            Text("(requires v\(Config.Daemon.minHelperVersion)+)")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
        if !isDaemonConnected || helperNeedsUpdate {
          HStack {
            Spacer()
            #if APPSTORE
            Button(helperNeedsUpdate ? "Update Helper..." : "Install Helper...") {
              HelperInstallService.shared.showInstallInstructions()
            }
            .font(.callout)
            .disabled(isInstallingHelper)
            #else
            Button(helperNeedsUpdate || helperDisconnectedForUpdate ? "Update Helper" : "Install Helper") {
              isInstallingHelper = true
              helperInstallResult = nil
              HelperInstallService.shared.autoInstall { success in
                DispatchQueue.main.async {
                  isInstallingHelper = false
                  helperInstallResult = success
                }
              }
            }
            .font(.callout)
            .disabled(isInstallingHelper)
            #endif
            Spacer()
          }
        }
        #if !APPSTORE
        if isDaemonConnected && !helperNeedsUpdate && !isInstallingHelper {
          HStack {
            Spacer()
            helperUpdateCheckButton
            Spacer()
          }
        }
        #endif
      } header: {
        Text("Helper Daemon")
      } footer: {
        Text("Required for power button detection, lock screen overlay, and pmset sleep prevention.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section {
        HStack {
          Spacer()
          if #available(macOS 26.0, *) {
            Button("Reset All Settings", role: .destructive) {
              showingResetConfirmation = true
            }
            .buttonStyle(.glass)
          } else {
            Button("Reset All Settings", role: .destructive) {
              showingResetConfirmation = true
            }
            .buttonStyle(.borderless)
          }
          Spacer()
        }
      }

      Section {
        HStack {
          Spacer()
          Text("\(Config.App.name) v\(Config.App.version)")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Spacer()
        }
      }
    }
    .formStyle(.grouped)
  }

  // MARK: - Triggers Tab

  private var triggersTab: some View {
    Form {
      Section {
        Toggle("Lid close detection", isOn: $triggerLidClose)
        Toggle("Power disconnect detection", isOn: $triggerPowerDisconnect)
        helperToggle("Power button detection", isOn: $triggerPowerButton)
          .onChange(of: triggerPowerButton) { _, newValue in
            if newValue && !helperAccessibilityGranted {
              triggerPowerButton = false
              openAccessibilitySettings()
            }
          }
      } header: {
        Text("Theft Mode Triggers")
      } footer: {
        if isDaemonConnected && !helperAccessibilityGranted {
          HStack(spacing: 4) {
            Text("Grant Accessibility permission to enable power button detection.")
            Button("Open Settings") { openAccessibilitySettings() }
              .buttonStyle(.link)
          }
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
      }

      Section {
        KeyboardShortcuts.Recorder("Shortcut", name: .toggleProtection)
        helperToggle("Lock screen when arming", isOn: $lockScreenOnShortcut)
      } header: {
        Text("Global Keyboard Shortcut")
      } footer: {
        Text("Press the shortcut anywhere to toggle protection. Requires Input Monitoring permission.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section { Text("💡 Right-click the menu bar icon to quickly toggle protection.")
          .font(.footnote).foregroundStyle(.secondary) }
    }
    .formStyle(.grouped)
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
    Form {
      Section {
        Toggle("Enable Bluetooth auto-arm", isOn: $bluetoothAutoArmEnabled)
        if bluetoothAutoArmEnabled {
          helperToggle("Lock screen when auto-arming", isOn: $lockScreenOnBluetoothArm)
        }
      } header: {
        Text("Auto-Arm")
      } footer: {
        Text("Automatically arms protection when all trusted Bluetooth devices leave range, and disarms when any returns.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section {
        KeyboardShortcuts.Recorder("Shortcut", name: .toggleBluetooth)
      } header: {
        Text("Global Keyboard Shortcut")
      } footer: {
        Text("Press the shortcut anywhere to toggle Bluetooth auto-arm. Requires Input Monitoring permission.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if bluetoothAutoArmEnabled {
        Section {
          LabeledContent("Arm delay") {
            HStack {
              Slider(value: $bluetoothArmGracePeriod, in: 60...300, step: 10)
              Text("\(Int(bluetoothArmGracePeriod))s")
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
            }
          }
        } header: {
          Text("Arm Delay")
        }

        Section {
          BluetoothDevicePickerView(trustedDevices: $trustedBLEDevices)
        } header: {
          Text("Devices")
        }
      }
    }
    .formStyle(.grouped)
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
      isDaemonConnected: isDaemonConnected,
      onConnect: { connectTelegram() }
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
    #if !APPSTORE
    autoUpdateEnabled = settings.autoUpdateEnabled
    #endif
    selectedAlarmSound = settings.alarmSound
    behaviorAutoAlarm = settings.behaviorAutoAlarm
    alarmVolume = Double(settings.alarmVolume)
    triggerLidClose = settings.triggerLidClose
    triggerPowerDisconnect = settings.triggerPowerDisconnect
    triggerPowerButton = settings.triggerPowerButton
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
    notifyAutoArm = settings.notifyAutoArm
    notifyProtectionToggle = settings.notifyProtectionToggle
    trackLocation = settings.trackLocation
    trackPublicIP = settings.trackPublicIP
    trackWiFi = settings.trackWiFi
    trackBattery = settings.trackBattery
    trackDeviceName = settings.trackDeviceName
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
    settings.triggerPowerDisconnect = triggerPowerDisconnect
    settings.triggerPowerButton = triggerPowerButton
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
    NotificationCenter.default.post(name: .bluetoothSettingsChanged, object: nil)

    settings.notifyAutoArm = notifyAutoArm
    settings.notifyProtectionToggle = notifyProtectionToggle
    settings.trackLocation = trackLocation
    settings.trackPublicIP = trackPublicIP
    settings.trackWiFi = trackWiFi
    settings.trackBattery = trackBattery
    settings.trackDeviceName = trackDeviceName

    #if !APPSTORE
    settings.autoUpdateEnabled = autoUpdateEnabled
    if autoUpdateEnabled {
      UpdateService.shared.startPeriodicChecks()
      HelperInstallService.shared.startPeriodicHelperChecks()
    } else {
      UpdateService.shared.stopPeriodicChecks()
      HelperInstallService.shared.stopPeriodicHelperChecks()
    }
    #endif

    if !settings.setupComplete {
      settings.setupComplete = true
    }

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

  #if !APPSTORE
  private var onLockScreenEnabled: (() -> Void)? { { requestContactsAndPopulate() } }
  private var onRetrieveContacts: (() -> Void)? { { retrieveFromContacts() } }
  #else
  private var onLockScreenEnabled: (() -> Void)? { nil }
  private var onRetrieveContacts: (() -> Void)? { nil }
  #endif

  #if !APPSTORE
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

  @ViewBuilder
  private var helperUpdateCheckButton: some View {
    let title = isCheckingForHelperUpdates ? "Checking..." : "Check for Helper Updates"
    if #available(macOS 26.0, *) {
      Button(title) { checkForHelperUpdates() }
        .buttonStyle(.glass).disabled(isCheckingForHelperUpdates).font(.callout)
    } else {
      Button(title) { checkForHelperUpdates() }
        .buttonStyle(.borderless).disabled(isCheckingForHelperUpdates).font(.callout)
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
  #endif

  private func helperToggle(_ title: String, isOn: Binding<Bool>) -> some View {
    Toggle(isOn: isOn) {
      HStack(spacing: 6) {
        Text(title)
        if !isDaemonConnected {
          Text("(requires Helper)")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }
    }
    .disabled(!isDaemonConnected)
  }
}

#if !APPSTORE
private func contactsPhoneNumber() -> String? {
  let store = CNContactStore()
  guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return nil }
  let keys: [CNKeyDescriptor] = [CNContactPhoneNumbersKey as CNKeyDescriptor]
  guard let me = try? store.unifiedMeContactWithKeys(toFetch: keys) else { return nil }
  let mobile = me.phoneNumbers.first { $0.label == CNLabelPhoneNumberMobile }
  return mobile?.value.stringValue ?? me.phoneNumbers.first?.value.stringValue
}
#endif
