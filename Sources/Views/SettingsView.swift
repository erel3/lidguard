import Contacts
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
  case general, triggers, protection, notifications

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: return "General"
    case .triggers: return "Triggers"
    case .protection: return "Protection"
    case .notifications: return "Notifications"
    }
  }

  var icon: String {
    switch self {
    case .general: return "gear"
    case .triggers: return "bolt.fill"
    case .protection: return "shield.fill"
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
  @State private var shortcutKeyCode: Int = -1
  @State private var shortcutModifiers: UInt = 0

  // Protection
  @State private var behaviorSleepPrevention: Bool = true
  @State private var sleepPreventionInstalled: Bool = false
  @State private var behaviorShutdownBlocking: Bool = true
  @State private var behaviorLockScreen: Bool = true
  @State private var behaviorAlarm: Bool = true
  @State private var behaviorAutoAlarm: Bool = false
  @State private var alarmVolume: Double = 100
  @State private var selectedAlarmSound: String = "Sosumi"

  // Notifications
  @State private var telegramBotToken: String = ""
  @State private var telegramChatId: String = ""
  @State private var telegramEnabled: Bool = true
  @State private var pushoverUserKey: String = ""
  @State private var pushoverApiToken: String = ""
  @State private var pushoverEnabled: Bool = true

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
  private let pmset = PmsetService.shared
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
      case .notifications:
        notificationsTab
      case nil:
        generalTab
      }
    }
    .frame(width: 600, height: 460)
    .onAppear(perform: loadSettings)
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
      } header: {
        Text("Contact Information")
      }

      Section {
        Toggle("Start at Login", isOn: $startAtLogin)
          .onChange(of: startAtLogin) { _, newValue in
            toggleLoginItem(newValue)
          }
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
        Toggle("Power button detection", isOn: $triggerPowerButton)
      } header: {
        Text("Theft Mode Triggers")
      } footer: {
        Text("Power button detection requires Accessibility permission.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section {
        Toggle("Enable global shortcut", isOn: $shortcutEnabled)
        if shortcutEnabled {
          LabeledContent("Shortcut") {
            HStack(spacing: 8) {
              ShortcutRecorderView(keyCode: $shortcutKeyCode, modifiers: $shortcutModifiers)
                .frame(width: 160, height: 24)
              if shortcutKeyCode >= 0 && shortcutModifiers != 0 {
                Button("Clear") {
                  shortcutKeyCode = -1
                  shortcutModifiers = 0
                }
                .buttonStyle(.borderless)
              }
            }
          }
        }
      } header: {
        Text("Global Keyboard Shortcut")
      } footer: {
        Text("Press the shortcut anywhere to enable protection and lock screen. Requires Accessibility permission.")
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
        Toggle("Sleep prevention (IOPMAssertion)", isOn: $behaviorSleepPrevention)
        LabeledContent("Sleep Prevention (pmset)") {
          if #available(macOS 26.0, *) {
            Button(sleepPreventionInstalled ? "Uninstall" : "Install") {
              toggleSleepPrevention()
            }
            .buttonStyle(.glass)
          } else {
            Button(sleepPreventionInstalled ? "Uninstall" : "Install") {
              toggleSleepPrevention()
            }
            .buttonStyle(.borderless)
          }
        }
      } header: {
        Text("Sleep")
      }

      Section {
        Toggle("Shutdown blocking", isOn: $behaviorShutdownBlocking)
        Toggle("Lock screen message", isOn: $behaviorLockScreen)
      } header: {
        Text("Defense")
      }

      Section {
        Toggle("Alarm enabled", isOn: $behaviorAlarm)
        if behaviorAlarm {
          Toggle("Auto-play on theft mode", isOn: $behaviorAutoAlarm)
          Picker("Alarm Sound", selection: $selectedAlarmSound) {
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
        }
      } header: {
        Text("Alarm")
      }
    }
    .formStyle(.grouped)
  }

  // MARK: - Notifications Tab

  private var notificationsTab: some View {
    Form {
      Section {
        LabeledContent("Bot Token") {
          SecureField("", text: $telegramBotToken)
            .textFieldStyle(.plain)
        }
        LabeledContent("Chat ID") {
          TextField("", text: $telegramChatId)
            .textFieldStyle(.plain)
        }
        Toggle("Enable notifications", isOn: $telegramEnabled)
      } header: {
        Text("Telegram")
      }

      Section {
        LabeledContent("User Key") {
          SecureField("", text: $pushoverUserKey)
            .textFieldStyle(.plain)
        }
        LabeledContent("API Token") {
          SecureField("", text: $pushoverApiToken)
            .textFieldStyle(.plain)
        }
        Toggle("Enable notifications", isOn: $pushoverEnabled)
      } header: {
        Text("Pushover")
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
    pushoverUserKey = settings.pushoverUserKey ?? ""
    pushoverApiToken = settings.pushoverApiToken ?? ""
    pushoverEnabled = settings.pushoverEnabled
    startAtLogin = loginItem.isEnabled
    autoUpdateEnabled = settings.autoUpdateEnabled
    sleepPreventionInstalled = pmset.isInstalled()
    selectedAlarmSound = settings.alarmSound
    behaviorAutoAlarm = settings.behaviorAutoAlarm
    alarmVolume = Double(settings.alarmVolume)
    triggerLidClose = settings.triggerLidClose
    triggerPowerDisconnect = settings.triggerPowerDisconnect
    triggerPowerButton = settings.triggerPowerButton
    shortcutEnabled = settings.shortcutEnabled
    shortcutKeyCode = settings.shortcutKeyCode
    shortcutModifiers = UInt(settings.shortcutModifiers)
    behaviorSleepPrevention = settings.behaviorSleepPrevention
    behaviorShutdownBlocking = settings.behaviorShutdownBlocking
    behaviorLockScreen = settings.behaviorLockScreen
    behaviorAlarm = settings.behaviorAlarm
  }

  private func saveSettings() {
    settings.contactName = contactName.isEmpty ? nil : contactName
    settings.contactPhone = contactPhone.isEmpty ? nil : contactPhone
    settings.telegramBotToken = telegramBotToken.isEmpty ? nil : telegramBotToken
    settings.telegramChatId = telegramChatId.isEmpty ? nil : telegramChatId
    settings.telegramEnabled = telegramEnabled
    settings.pushoverUserKey = pushoverUserKey.isEmpty ? nil : pushoverUserKey
    settings.pushoverApiToken = pushoverApiToken.isEmpty ? nil : pushoverApiToken
    settings.pushoverEnabled = pushoverEnabled
    settings.alarmSound = selectedAlarmSound
    settings.behaviorAutoAlarm = behaviorAutoAlarm
    settings.alarmVolume = Int(alarmVolume)
    settings.triggerLidClose = triggerLidClose
    settings.triggerPowerDisconnect = triggerPowerDisconnect
    settings.triggerPowerButton = triggerPowerButton
    settings.shortcutEnabled = shortcutEnabled
    settings.shortcutKeyCode = shortcutKeyCode
    settings.shortcutModifiers = UInt(shortcutModifiers)
    NotificationCenter.default.post(name: .shortcutSettingsChanged, object: nil)
    settings.behaviorSleepPrevention = behaviorSleepPrevention
    settings.behaviorShutdownBlocking = behaviorShutdownBlocking
    settings.behaviorLockScreen = behaviorLockScreen
    settings.behaviorAlarm = behaviorAlarm

    settings.autoUpdateEnabled = autoUpdateEnabled
    if autoUpdateEnabled {
      UpdateService.shared.startPeriodicChecks()
    } else {
      UpdateService.shared.stopPeriodicChecks()
    }

    ActivityLog.logAsync(.system, "Settings saved")
  }

  private func resetSettings() {
    settings.resetAll()
    loadSettings()
    ActivityLog.logAsync(.system, "All settings reset")
  }

  private func toggleSleepPrevention() {
    if sleepPreventionInstalled {
      _ = pmset.uninstall()
    } else {
      _ = pmset.install()
    }
    sleepPreventionInstalled = pmset.isInstalled()
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
}
