import Contacts
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
  @State private var autoUpdateEnabled: Bool = true
  @State private var isCheckingForUpdates: Bool = false

  // Triggers
  @State private var triggerLidClose: Bool = true
  @State private var triggerPowerDisconnect: Bool = true
  @State private var triggerPowerButton: Bool = false

  // Global Shortcut
  @State private var shortcutEnabled: Bool = false

  // Protection
  @State private var behaviorSleepPrevention: Bool = true
  @State private var behaviorLidCloseSleep: Bool = true
  @State private var behaviorShutdownBlocking: Bool = true
  @State private var behaviorLockScreen: Bool = true
  @State private var behaviorAlarm: Bool = true
  @State private var behaviorAutoAlarm: Bool = false
  @State private var alarmVolume: Double = 100
  @State private var selectedAlarmSound: String = "Sosumi"
  @State private var offlineSirenEnabled: Bool = false

  // Bluetooth
  @State private var bluetoothAutoArmEnabled: Bool = false
  @State private var bluetoothArmGracePeriod: Double = 30
  @State private var trustedBLEDevices: [TrustedBLEDevice] = []
  @State private var btShortcutEnabled: Bool = false

  // Notifications
  @State private var telegramBotToken: String = ""
  @State private var telegramChatId: String = ""
  @State private var telegramEnabled: Bool = true

  @State private var isDaemonConnected = false
  @State private var daemonVersion: String?
  @State private var helperNeedsUpdate = false
  @State private var isInstallingHelper = false
  @State private var helperInstallResult: Bool?
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
    }
    .onReceive(NotificationCenter.default.publisher(for: .daemonConnectionChanged)) { _ in
      isDaemonConnected = TheftProtectionService.daemonConnected
      daemonVersion = TheftProtectionService.daemonVersion
      helperNeedsUpdate = TheftProtectionService.helperNeedsUpdate
      if isDaemonConnected { helperInstallResult = nil }
    }
    .onReceive(NotificationCenter.default.publisher(for: .helperVersionChanged)) { _ in
      daemonVersion = TheftProtectionService.daemonVersion
      helperNeedsUpdate = TheftProtectionService.helperNeedsUpdate
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
          } else {
            Image(systemName: "xmark.circle")
              .foregroundStyle(.secondary)
            Text("Helper Not Connected")
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
            Button(helperNeedsUpdate ? "Update Helper" : "Install Helper") {
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
      } header: {
        Text("Theft Mode Triggers")
      } footer: {
        if isDaemonConnected {
          Text("Power button detection requires Accessibility permission for the Helper.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      Section {
        KeyboardShortcuts.Recorder("Shortcut", name: .toggleProtection)
      } header: {
        Text("Global Keyboard Shortcut")
      } footer: {
        Text("Press the shortcut anywhere to enable protection and lock screen. Requires Input Monitoring permission.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  // MARK: - Protection Tab

  private var protectionTab: some View {
    Form {
      Section {
        Toggle("Idle sleep prevention", isOn: $behaviorSleepPrevention)
        helperToggle("Lid-close sleep prevention", isOn: $behaviorLidCloseSleep)
      } header: {
        Text("Sleep")
      } footer: {
        Text("Idle prevents system sleep via IOPMAssertion. Lid-close uses pmset disablesleep via Helper to keep the Mac running with lid closed.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section {
        Toggle("Shutdown blocking", isOn: $behaviorShutdownBlocking)
        helperToggle("Lock screen message", isOn: $behaviorLockScreen)
          .onChange(of: behaviorLockScreen) { _, newValue in
            if newValue && isDaemonConnected {
              requestContactsAndPopulate()
            }
          }
        if behaviorLockScreen {
          LabeledContent("Name") {
            TextField("", text: $contactName)
              .textFieldStyle(.plain)
          }
          LabeledContent("Phone") {
            TextField("", text: $contactPhone)
              .textFieldStyle(.plain)
          }
          LabeledContent {
            Button("Retrieve from Contacts") {
              retrieveFromContacts()
            }
            .buttonStyle(.borderless)
          } label: {
            EmptyView()
          }
        }
      } header: {
        Text("Defense")
      }

      Section {
        Toggle("Auto-play on theft mode", isOn: $behaviorAutoAlarm)
        Picker("Sound", selection: $selectedAlarmSound) {
          ForEach(alarmSounds, id: \.self) { sound in
            Text(sound).tag(sound)
          }
        }
        .onChange(of: selectedAlarmSound) { _, newValue in
          if newValue == "Siren" {
            AlarmAudioManager.shared.previewSiren()
          } else {
            NSSound(named: newValue)?.play()
          }
        }
        LabeledContent("Volume") {
          HStack {
            Slider(value: $alarmVolume, in: 10...100, step: 10)
            Text("\(Int(alarmVolume))%")
              .monospacedDigit()
              .frame(width: 40, alignment: .trailing)
          }
        }
        Toggle("Siren when offline", isOn: $offlineSirenEnabled)
      } header: {
        Text("Alarm")
      } footer: {
        Text("Alarm can be triggered via Telegram or keyboard shortcut. Offline siren plays automatically when Telegram is unavailable.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  // MARK: - Bluetooth Tab

  private var bluetoothTab: some View {
    Form {
      Section {
        Toggle("Enable Bluetooth auto-arm", isOn: $bluetoothAutoArmEnabled)
      } header: {
        Text("Auto-Arm")
      } footer: {
        Text("Automatically arms protection when all trusted Bluetooth devices leave range, and disarms when any returns.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section {
        Toggle("Enable global shortcut", isOn: $btShortcutEnabled)
        if btShortcutEnabled {
          KeyboardShortcuts.Recorder("Shortcut", name: .toggleBluetooth)
        }
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
    Form {
      Section {
        Toggle("Enable Telegram notifications", isOn: $telegramEnabled)
        if telegramEnabled {
          LabeledContent("Bot Token") {
            SecureField("", text: $telegramBotToken)
              .textFieldStyle(.plain)
          }
          LabeledContent("Chat ID") {
            TextField("", text: $telegramChatId)
              .textFieldStyle(.plain)
          }
        }
      } header: {
        Text("Telegram")
      } footer: {
        if !telegramEnabled {
          Text("Telegram notifications are disabled. The app will still protect your device locally (alarm, lock screen).")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

    }
    .formStyle(.grouped)
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
    triggerPowerDisconnect = settings.triggerPowerDisconnect
    triggerPowerButton = settings.triggerPowerButton
    shortcutEnabled = settings.shortcutEnabled
    behaviorSleepPrevention = settings.behaviorSleepPrevention
    behaviorLidCloseSleep = settings.behaviorLidCloseSleep
    behaviorShutdownBlocking = settings.behaviorShutdownBlocking
    behaviorLockScreen = settings.behaviorLockScreen
    behaviorAlarm = settings.behaviorAlarm
    offlineSirenEnabled = settings.offlineSirenEnabled
    bluetoothAutoArmEnabled = settings.bluetoothAutoArmEnabled
    bluetoothArmGracePeriod = settings.bluetoothArmGracePeriod
    trustedBLEDevices = settings.trustedBLEDevices
    btShortcutEnabled = settings.btShortcutEnabled
  }

  private func saveSettings() {
    settings.contactName = contactName.isEmpty ? nil : contactName
    settings.contactPhone = contactPhone.isEmpty ? nil : contactPhone
    settings.telegramBotToken = telegramBotToken.isEmpty ? nil : telegramBotToken
    settings.telegramChatId = telegramChatId.isEmpty ? nil : telegramChatId
    settings.telegramEnabled = telegramEnabled
    settings.alarmSound = selectedAlarmSound
    settings.behaviorAutoAlarm = behaviorAutoAlarm
    settings.alarmVolume = Int(alarmVolume)
    settings.triggerLidClose = triggerLidClose
    settings.triggerPowerDisconnect = triggerPowerDisconnect
    settings.triggerPowerButton = triggerPowerButton
    settings.shortcutEnabled = shortcutEnabled
    NotificationCenter.default.post(name: .shortcutSettingsChanged, object: nil)
    settings.behaviorSleepPrevention = behaviorSleepPrevention
    settings.behaviorLidCloseSleep = behaviorLidCloseSleep
    settings.behaviorShutdownBlocking = behaviorShutdownBlocking
    settings.behaviorLockScreen = behaviorLockScreen
    settings.behaviorAlarm = behaviorAlarm
    settings.offlineSirenEnabled = offlineSirenEnabled

    settings.bluetoothAutoArmEnabled = bluetoothAutoArmEnabled
    settings.bluetoothArmGracePeriod = bluetoothArmGracePeriod
    settings.trustedBLEDevices = trustedBLEDevices
    settings.btShortcutEnabled = btShortcutEnabled
    NotificationCenter.default.post(name: .bluetoothSettingsChanged, object: nil)

    settings.autoUpdateEnabled = autoUpdateEnabled
    if autoUpdateEnabled {
      UpdateService.shared.startPeriodicChecks()
    } else {
      UpdateService.shared.stopPeriodicChecks()
    }

    if !settings.setupComplete {
      settings.setupComplete = true
    }

    ActivityLog.logAsync(.system, "Settings saved")
  }

  private func resetSettings() {
    settings.resetAll()
    loadSettings()
    ActivityLog.logAsync(.system, "All settings reset")
  }

  private func toggleLoginItem(_ enable: Bool) {
    if enable {
      _ = loginItem.enable()
    } else {
      _ = loginItem.disable()
    }
  }

  private func checkForUpdates() {
    isCheckingForUpdates = true
    UpdateService.shared.checkForUpdates(silent: false) {
      DispatchQueue.main.async {
        isCheckingForUpdates = false
      }
    }
  }

  private func requestContactsAndPopulate() {
    settings.requestContactsAccess { granted in
      if granted {
        DispatchQueue.main.async {
          if contactName.isEmpty {
            let name = NSFullUserName()
            if !name.isEmpty { contactName = name }
          }
          if contactPhone.isEmpty, let phone = getMyCardPhone() {
            contactPhone = phone
          }
        }
      }
    }
  }

  private func retrieveFromContacts() {
    let ownerName = NSFullUserName()
    if !ownerName.isEmpty {
      contactName = ownerName
    }

    settings.requestContactsAccess { granted in
      if granted {
        DispatchQueue.main.async {
          if let phone = getMyCardPhone() {
            contactPhone = phone
          }
        }
      }
    }
  }

  private func getMyCardPhone() -> String? {
    let store = CNContactStore()
    guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
      return nil
    }
    let keys: [CNKeyDescriptor] = [CNContactPhoneNumbersKey as CNKeyDescriptor]
    guard let me = try? store.unifiedMeContactWithKeys(toFetch: keys) else {
      return nil
    }
    let mobile = me.phoneNumbers.first { $0.label == CNLabelPhoneNumberMobile }
    return mobile?.value.stringValue ?? me.phoneNumbers.first?.value.stringValue
  }

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
