import Foundation
import Network
import os.log

protocol DaemonIPCDelegate: AnyObject {
  func daemonDidConnect(_ client: DaemonIPCClient, version: String?)
  func daemonDidDisconnect(_ client: DaemonIPCClient)
  func daemonDidReceiveStatus(_ client: DaemonIPCClient, accessibilityGranted: Bool)
  func daemonDidReceivePowerButtonPress(_ client: DaemonIPCClient)
  func daemonDidDetectMotion(_ client: DaemonIPCClient, detail: String, session: UInt64)
  func daemonDidUpdateMotionSupport(_ client: DaemonIPCClient, supported: Bool)
}

protocol DaemonIPC: AnyObject {
  var delegate: DaemonIPCDelegate? { get set }
  var isConnected: Bool { get }
  var motionSupported: Bool { get }
  func connect()
  func reconnectNow()
  func disconnect()
  func enablePmset()
  func disablePmset()
  func lockScreen()
  func showLockScreen(contactName: String, contactPhone: String, message: String)
  func hideLockScreen()
  func enablePowerButton()
  func disablePowerButton()
  func enableMotionMonitoring()
  func disableMotionMonitoring()
  func getStatus()
}

final class DaemonIPCClient: DaemonIPC {
  weak var delegate: DaemonIPCDelegate?

  private let queue = DispatchQueue(label: "com.lidguard.daemon.ipc")
  private var connection: NWConnection?
  private var state: ConnectionState = .disconnected
  private var shouldReconnect = false
  private var reconnectDelay: TimeInterval = Config.Daemon.reconnectBaseDelay
  private var reconnectTimer: DispatchSourceTimer?
  private var buffer = Data()
  private var pendingCommands: [IPCCommand] = []
  private var hasLoggedConnectionRefused = false

  private enum ConnectionState {
    case disconnected
    case connecting
    case authenticating
    case connected
  }

  var isConnected: Bool {
    queue.sync { state == .connected }
  }

  private var _motionSupported: Bool = true  // optimistic until helper reports otherwise
  var motionSupported: Bool {
    queue.sync { _motionSupported }
  }

  // Most recently observed MotionMonitor session — monotonically increasing.
  // motion_detected events with a session below this are stale (in-flight
  // during a recalibrate stop+start) and must be dropped.
  private var _motionSession: UInt64 = 0
  var motionSession: UInt64 { queue.sync { _motionSession } }

  // MARK: - Public API

  func connect() {
    queue.async { [self] in
      guard state == .disconnected else { return }
      shouldReconnect = true
      startConnection()
    }
  }

  func reconnectNow() {
    queue.async { [self] in
      cancelReconnect()
      tearDown()
      reconnectDelay = Config.Daemon.reconnectBaseDelay
      shouldReconnect = true
      startConnection()
    }
  }

  func disconnect() {
    queue.async { [self] in
      shouldReconnect = false
      cancelReconnect()
      tearDown()
    }
  }

  func enablePmset() {
    send(IPCCommand(type: "enable_pmset"))
  }

  func disablePmset() {
    send(IPCCommand(type: "disable_pmset"))
  }

  func lockScreen() {
    send(IPCCommand(type: "lock_screen"))
  }

  func showLockScreen(contactName: String, contactPhone: String, message: String) {
    send(IPCCommand(
      type: "show_lock_screen",
      contactName: contactName,
      contactPhone: contactPhone,
      message: message
    ))
  }

  func hideLockScreen() {
    send(IPCCommand(type: "hide_lock_screen"))
  }

  func enablePowerButton() {
    send(IPCCommand(type: "enable_power_button"))
  }

  func disablePowerButton() {
    send(IPCCommand(type: "disable_power_button"))
  }

  func enableMotionMonitoring() {
    send(IPCCommand(type: "start_motion_monitoring"))
  }

  func disableMotionMonitoring() {
    send(IPCCommand(type: "stop_motion_monitoring"))
  }

  func getStatus() {
    send(IPCCommand(type: "get_status"))
  }

  // MARK: - Connection

  private func startConnection() {
    state = .connecting
    let endpoint = NWEndpoint.hostPort(
      host: NWEndpoint.Host(Config.Daemon.host),
      port: NWEndpoint.Port(rawValue: Config.Daemon.port)!
    )
    let conn = NWConnection(to: endpoint, using: .tcp)
    connection = conn

    conn.stateUpdateHandler = { [weak self] newState in
      self?.queue.async {
        self?.handleConnectionState(newState)
      }
    }
    conn.start(queue: queue)
  }

  private func handleConnectionState(_ newState: NWConnection.State) {
    switch newState {
    case .ready:
      state = .authenticating
      hasLoggedConnectionRefused = false
      startReceive()
      authenticate()

    case .failed(let error):
      logConnectionError(error)
      tearDown()
      scheduleReconnect()

    case .waiting(let error):
      logConnectionError(error)
      tearDown()
      scheduleReconnect()

    case .cancelled:
      break

    default:
      break
    }
  }

  private func logConnectionError(_ error: NWError) {
    if case .posix(let code) = error, code == .ECONNREFUSED {
      if !hasLoggedConnectionRefused {
        hasLoggedConnectionRefused = true
        Logger.daemon.info("Helper daemon not available (connection refused)")
      }
    } else {
      Logger.daemon.error("Connection error: \(error.localizedDescription)")
    }
  }

  private func tearDown() {
    connection?.cancel()
    connection = nil
    buffer.removeAll()
    pendingCommands.removeAll()
    let wasConnected = state == .connected || state == .authenticating
    state = .disconnected
    if wasConnected {
      notifyMainThread { [weak self] in
        guard let self else { return }
        self.delegate?.daemonDidDisconnect(self)
      }
    }
  }

  // MARK: - Auth

  private func authenticate() {
    let cmd = IPCCommand(type: "auth")
    sendImmediate(cmd)
  }

  // MARK: - Send

  private func send(_ command: IPCCommand) {
    queue.async { [self] in
      switch state {
      case .connected:
        sendImmediate(command)
      case .connecting, .authenticating:
        pendingCommands.append(command)
      case .disconnected:
        break
      }
    }
  }

  private func sendImmediate(_ command: IPCCommand) {
    guard let conn = connection else { return }
    do {
      var data = try JSONEncoder().encode(command)
      data.append(0x0A) // newline
      conn.send(content: data, completion: .contentProcessed { [weak self] error in
        if let error {
          Logger.daemon.error("Send error: \(error.localizedDescription)")
          self?.queue.async { self?.tearDown(); self?.scheduleReconnect() }
        }
      })
    } catch {
      Logger.daemon.error("Encode error: \(error.localizedDescription)")
    }
  }

  private func flushPendingCommands() {
    let commands = pendingCommands
    pendingCommands.removeAll()
    for cmd in commands {
      sendImmediate(cmd)
    }
  }

  // MARK: - Receive

  private func startReceive() {
    connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
      self?.queue.async {
        if let data, !data.isEmpty {
          self?.buffer.append(data)
          self?.processBuffer()
        }
        if let error {
          Logger.daemon.error("Receive error: \(error.localizedDescription)")
          self?.tearDown()
          self?.scheduleReconnect()
          return
        }
        if isComplete {
          Logger.daemon.info("Daemon closed connection")
          self?.tearDown()
          self?.scheduleReconnect()
          return
        }
        self?.startReceive()
      }
    }
  }

  private func processBuffer() {
    while let newlineIndex = buffer.firstIndex(of: 0x0A) {
      let lineData = buffer[buffer.startIndex..<newlineIndex]
      buffer = Data(buffer[buffer.index(after: newlineIndex)...])

      guard !lineData.isEmpty else { continue }
      do {
        let message = try JSONDecoder().decode(IPCMessage.self, from: lineData)
        handleMessage(message)
      } catch {
        Logger.daemon.error("Decode error: \(error.localizedDescription)")
      }
    }
  }

  // MARK: - Message Handling

  private func handleMessage(_ message: IPCMessage) {
    switch message.type {
    case "auth_result":
      handleAuthResult(message)

    case "power_button_pressed":
      notifyMainThread { [weak self] in
        guard let self else { return }
        self.delegate?.daemonDidReceivePowerButtonPress(self)
      }

    case "motion_detected":
      let detail = message.motionDetail ?? ""
      let session = message.motionSession ?? 0
      // Drop events from older sessions (in-flight during a recalibrate).
      // Forward-jump cases are handled: a new session updates our cache.
      if session < _motionSession {
        Logger.daemon.info("Dropping stale motion_detected (session=\(session) < \(self._motionSession))")
        return
      }
      _motionSession = session
      notifyMainThread { [weak self] in
        guard let self else { return }
        self.delegate?.daemonDidDetectMotion(self, detail: detail, session: session)
      }

    case "status":
      handleStatus(message)

    case "error":
      Logger.daemon.error("Daemon error: \(message.message ?? "unknown")")

    default:
      Logger.daemon.warning("Unknown message type: \(message.type)")
    }
  }

  private func handleAuthResult(_ message: IPCMessage) {
    if message.success == true {
      state = .connected
      reconnectDelay = Config.Daemon.reconnectBaseDelay
      let version = message.version
      Logger.daemon.info("Authenticated with helper daemon (v\(version ?? "unknown"))")
      flushPendingCommands()
      notifyMainThread { [weak self] in
        guard let self else { return }
        self.delegate?.daemonDidConnect(self, version: version)
      }
    } else {
      Logger.daemon.error("Authentication failed — code signing verification rejected")
      shouldReconnect = false
      tearDown()
    }
  }

  private func handleStatus(_ message: IPCMessage) {
    let pmsetOn = message.pmset ?? false
    let lockOn = message.lockScreen ?? false
    let powerOn = message.powerButton ?? false
    let axGranted = message.accessibilityGranted ?? false
    let motionOn = message.motion ?? false
    let motionSupport = message.motionSupported ?? true
    let previousSupport = _motionSupported
    _motionSupported = motionSupport
    if let session = message.motionSession, session > _motionSession {
      _motionSession = session
    }
    Logger.daemon.info(
      "Daemon status — pmset: \(pmsetOn), lockScreen: \(lockOn), powerButton: \(powerOn), ax: \(axGranted), motion: \(motionOn), motionSup: \(motionSupport)"
    )
    notifyMainThread { [weak self] in
      guard let self else { return }
      self.delegate?.daemonDidReceiveStatus(self, accessibilityGranted: axGranted)
      if motionSupport != previousSupport {
        self.delegate?.daemonDidUpdateMotionSupport(self, supported: motionSupport)
      }
    }
  }

  // MARK: - Reconnect

  private func scheduleReconnect() {
    guard shouldReconnect else { return }
    cancelReconnect()

    let delay = reconnectDelay
    reconnectDelay = min(reconnectDelay * 2, Config.Daemon.reconnectMaxDelay)

    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + delay)
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      self.reconnectTimer = nil
      guard self.state == .disconnected, self.shouldReconnect else { return }
      Logger.daemon.info("Reconnecting to helper daemon...")
      self.startConnection()
    }
    reconnectTimer = timer
    timer.resume()
  }

  private func cancelReconnect() {
    reconnectTimer?.cancel()
    reconnectTimer = nil
  }

  // MARK: - Thread Helpers

  private func notifyMainThread(_ block: @escaping () -> Void) {
    CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue, block)
    CFRunLoopWakeUp(CFRunLoopGetMain())
  }
}
