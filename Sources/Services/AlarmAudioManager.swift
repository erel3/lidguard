import AVFoundation
import CoreAudio
import os.log

@MainActor
final class AlarmAudioManager {
  static let shared = AlarmAudioManager()

  private var player: AVAudioPlayer?
  private var audioEngine: AVAudioEngine?
  private var sourceNode: AVAudioSourceNode?
  private(set) var isPlaying = false
  private var savedSystemVolume: Float?
  private let lock = NSLock()
  private static let savedVolumeKey = "AlarmAudioManager.savedSystemVolume"

  private var monitoredDeviceID: AudioObjectID = 0
  private var volumeListenerBlock: AudioObjectPropertyListenerBlock?

  private init() {
    restoreSystemVolumeIfNeeded()
  }

  func play() {
    lock.lock()
    defer { lock.unlock() }

    guard !isPlaying else { return }
    isPlaying = true

    savedSystemVolume = getSystemVolume()
    persistSavedVolume(savedSystemVolume)
    setSystemVolume(1.0)
    startVolumeMonitoring()

    let soundName = SettingsService.shared.alarmSound
    let volume = Float(SettingsService.shared.alarmVolume) / 100.0

    if soundName == "Siren" {
      playSiren(volume: volume)
    } else {
      playSystemSound(soundName, volume: volume)
    }
  }

  func stop() {
    lock.lock()
    defer { lock.unlock() }

    guard isPlaying else { return }
    isPlaying = false
    stopVolumeMonitoring()

    player?.stop()
    player = nil
    audioEngine?.stop()
    audioEngine = nil
    sourceNode = nil

    if let saved = savedSystemVolume {
      setSystemVolume(saved)
      savedSystemVolume = nil
      clearPersistedVolume()
    }

    Logger.system.info("Alarm stopped")
    ActivityLog.logAsync(.system, "Alarm stopped")
  }

  func previewSiren() {
    lock.lock()
    guard audioEngine == nil else { lock.unlock(); return }

    let engine = AVAudioEngine()
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    var phase: Double = 0
    var time: Double = 0

    var phase2: Double = 0

    let source = AVAudioSourceNode { _, _, frameCount, bufferList -> OSStatus in
      let buffer = UnsafeMutableAudioBufferListPointer(bufferList)
      for frame in 0..<Int(frameCount) {
        let sweep = (1.0 + sin(2.0 * .pi * time / 0.7)) / 2.0
        let freq = 500.0 + (1400.0 - 500.0) * sweep

        let fundamental = sin(phase)
        let harmonic3 = sin(phase * 3.0) * 0.3
        let harmonic5 = sin(phase * 5.0) * 0.15
        let raw = fundamental + harmonic3 + harmonic5
        let clipped = tanh(raw * 1.5)
        let detune = sin(phase2) * 0.25
        let sample = Float(clipped + detune) * 0.28

        buffer[0].mData?.assumingMemoryBound(to: Float.self)[frame] = sample
        phase += 2.0 * .pi * freq / 44100.0
        phase2 += 2.0 * .pi * (freq * 1.02) / 44100.0
        if phase > 2.0 * .pi { phase -= 2.0 * .pi }
        if phase2 > 2.0 * .pi { phase2 -= 2.0 * .pi }
        time += 1.0 / 44100.0
      }
      return noErr
    }

    engine.attach(source)
    engine.connect(source, to: engine.mainMixerNode, format: format)

    do {
      try engine.start()
      self.audioEngine = engine
      self.sourceNode = source
    } catch {
      lock.unlock()
      return
    }
    lock.unlock()

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
      guard let self = self else { return }
      self.lock.lock()
      self.audioEngine?.stop()
      self.audioEngine = nil
      self.sourceNode = nil
      self.lock.unlock()
    }
  }

  // MARK: - Siren (synthesized)

  private func playSiren(volume: Float) {
    let sampleRate: Double = 44100
    let lowFreq: Double = 500
    let highFreq: Double = 1400
    let sweepPeriod: Double = 0.7

    var phase: Double = 0
    var phase2: Double = 0
    var time: Double = 0

    let engine = AVAudioEngine()
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

    let source = AVAudioSourceNode { _, _, frameCount, bufferList -> OSStatus in
      let buffer = UnsafeMutableAudioBufferListPointer(bufferList)
      for frame in 0..<Int(frameCount) {
        let sweep = (1.0 + sin(2.0 * .pi * time / sweepPeriod)) / 2.0
        let freq = lowFreq + (highFreq - lowFreq) * sweep

        // Primary tone with odd harmonics for harsh timbre
        let fundamental = sin(phase)
        let harmonic3 = sin(phase * 3.0) * 0.3
        let harmonic5 = sin(phase * 5.0) * 0.15
        let raw = fundamental + harmonic3 + harmonic5

        // Soft clipping for aggressive edge
        let clipped = tanh(raw * 1.5)

        // Secondary detuned oscillator for beating/width
        let detune = sin(phase2) * 0.25
        let sample = Float(clipped + detune) * 0.7

        buffer[0].mData?.assumingMemoryBound(to: Float.self)[frame] = sample
        phase += 2.0 * .pi * freq / sampleRate
        phase2 += 2.0 * .pi * (freq * 1.02) / sampleRate
        if phase > 2.0 * .pi { phase -= 2.0 * .pi }
        if phase2 > 2.0 * .pi { phase2 -= 2.0 * .pi }
        time += 1.0 / sampleRate
      }
      return noErr
    }

    engine.attach(source)
    engine.connect(source, to: engine.mainMixerNode, format: format)
    engine.mainMixerNode.outputVolume = volume

    do {
      try engine.start()
      self.audioEngine = engine
      self.sourceNode = source
      Logger.system.info("Siren alarm started")
      ActivityLog.logAsync(.system, "Alarm started: Siren")
    } catch {
      Logger.system.error("Failed to start siren: \(error.localizedDescription)")
      revertSystemVolume()
    }
  }

  // MARK: - System Volume

  private func getSystemVolume() -> Float? {
    var deviceID = AudioObjectID(kAudioObjectSystemObject)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
    )
    guard status == noErr else {
      Logger.system.error("Failed to get default output device: OSStatus \(status)")
      return nil
    }

    var volume: Float32 = 0
    size = UInt32(MemoryLayout<Float32>.size)
    address.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
    address.mScope = kAudioDevicePropertyScopeOutput
    let volStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
    guard volStatus == noErr else {
      Logger.system.error("Failed to read system volume: OSStatus \(volStatus)")
      return nil
    }
    return volume
  }

  private func setSystemVolume(_ volume: Float) {
    var deviceID = AudioObjectID(kAudioObjectSystemObject)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
    )
    guard status == noErr else {
      Logger.system.error("Failed to get default output device for volume set: OSStatus \(status)")
      return
    }

    var vol = volume
    size = UInt32(MemoryLayout<Float32>.size)
    address.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
    address.mScope = kAudioDevicePropertyScopeOutput
    let setStatus = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &vol)
    if setStatus != noErr {
      Logger.system.error("Failed to set system volume: OSStatus \(setStatus)")
    }
  }

  private func persistSavedVolume(_ volume: Float?) {
    guard let volume = volume else { return }
    UserDefaults.standard.set(volume, forKey: Self.savedVolumeKey)
  }

  private func clearPersistedVolume() {
    UserDefaults.standard.removeObject(forKey: Self.savedVolumeKey)
  }

  private func restoreSystemVolumeIfNeeded() {
    guard UserDefaults.standard.object(forKey: Self.savedVolumeKey) != nil else { return }
    let volume = UserDefaults.standard.float(forKey: Self.savedVolumeKey)
    setSystemVolume(volume)
    clearPersistedVolume()
    Logger.system.info("Restored system volume to \(String(format: "%.0f%%", volume * 100)) after previous session")
  }

  /// Reverts system volume on playback failure. Called from within play() while lock is held.
  private func revertSystemVolume() {
    isPlaying = false
    stopVolumeMonitoring()
    if let saved = savedSystemVolume {
      setSystemVolume(saved)
      savedSystemVolume = nil
      clearPersistedVolume()
    }
  }

  // MARK: - Volume Enforcement

  /// Registers a CoreAudio listener that snaps volume back to max whenever it changes during alarm playback.
  private func startVolumeMonitoring() {
    var deviceID = AudioObjectID(kAudioObjectSystemObject)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
    ) == noErr else { return }

    monitoredDeviceID = deviceID

    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      MainActor.assumeIsolated {
        guard let self, self.isPlaying else { return }
        if let current = self.getSystemVolume(), current < 1.0 {
          self.setSystemVolume(1.0)
        }
      }
    }
    volumeListenerBlock = block

    var volAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectAddPropertyListenerBlock(deviceID, &volAddress, .main, block)
  }

  /// Removes the CoreAudio volume listener.
  private func stopVolumeMonitoring() {
    guard monitoredDeviceID != 0, let block = volumeListenerBlock else { return }

    var volAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectRemovePropertyListenerBlock(monitoredDeviceID, &volAddress, .main, block)
    monitoredDeviceID = 0
    volumeListenerBlock = nil
  }

  // MARK: - System Sound

  private func playSystemSound(_ soundName: String, volume: Float) {
    let url = URL(fileURLWithPath: "/System/Library/Sounds/\(soundName).aiff")
    guard FileManager.default.fileExists(atPath: url.path) else {
      Logger.system.error("Alarm sound not found: \(soundName)")
      revertSystemVolume()
      return
    }

    do {
      player = try AVAudioPlayer(contentsOf: url)
      player?.volume = volume
      player?.numberOfLoops = -1
      player?.play()
      Logger.system.info("Alarm started: \(soundName)")
      ActivityLog.logAsync(.system, "Alarm started: \(soundName)")
    } catch {
      Logger.system.error("Failed to play alarm: \(error.localizedDescription)")
      revertSystemVolume()
    }
  }
}
