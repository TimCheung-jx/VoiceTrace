import AVFoundation
import Foundation

protocol VTLocalCapture: AnyObject {
  var onEvent: ((String, Int) -> Void)? { get set }
  func start(
    directory: URL, offset: Double, yield: @escaping (Data) -> Void,
    level: @escaping (Float) -> Void, interrupted: @escaping () -> Void, fail: @escaping () -> Void)
    async throws
  func duration() -> Double
  func stop() throws -> (URL, Double)?
}
// base仅在worker队列读写，事件回调由锁保护。
final class VTSystemCapture: VTLocalCapture, @unchecked Sendable {
  private let worker = DispatchQueue(label: "org.voicetrace.capture.start", qos: .userInitiated)
  private var base: AudioCapture?
  private let eventLock = NSLock()
  private var eventHandler: ((String, Int) -> Void)?
  var onEvent: ((String, Int) -> Void)? {
    get {
      eventLock.lock()
      defer { eventLock.unlock() }
      return eventHandler
    }
    set {
      eventLock.lock()
      eventHandler = newValue
      eventLock.unlock()
    }
  }
  func start(
    directory: URL, offset: Double, yield: @escaping (Data) -> Void,
    level: @escaping (Float) -> Void, interrupted: @escaping () -> Void, fail: @escaping () -> Void
  ) async throws {
    try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
      worker.async {
        do {
          let capture = AudioCapture()
          capture.onEvent = self.onEvent
          try capture.start(
            directory: directory, offset: offset, yield: yield, level: level,
            interrupted: interrupted, fail: fail)
          self.base = capture
          done.resume()
        } catch { done.resume(throwing: error) }
      }
    }
  }
  func duration() -> Double { worker.sync { base?.duration() ?? 0 } }
  func stop() throws -> (URL, Double)? { try worker.sync { try base?.stop() } }
}

@MainActor protocol VTSpeechSocket: AnyObject {
  func resume()
  func send(_ message: URLSessionWebSocketTask.Message) async throws
  func receive() async throws -> URLSessionWebSocketTask.Message
  func close()
}
@MainActor final class VTURLSpeechSocket: VTSpeechSocket {
  let task: URLSessionWebSocketTask
  init(_ request: URLRequest) { task = Network.shared.session.webSocketTask(with: request) }
  func resume() { task.resume() }
  func send(_ message: URLSessionWebSocketTask.Message) async throws {
    try await task.send(message)
  }
  func receive() async throws -> URLSessionWebSocketTask.Message { try await task.receive() }
  func close() { task.cancel(with: .normalClosure, reason: nil) }
}

// 本地采集与识别连接独立；重连只接续新音频，缺口保留在本地，需会后补转写。
@MainActor final class VTRecorder {
  enum State: String {
    case idle = "未开始"
    case starting = "正在启动麦克风"
    case recording = "录音中"
    case paused = "已暂停"
    case finishing = "正在收尾"
    case ended = "已结束"
  }
  private(set) var state: State = .idle
  private(set) var health = VTRecognitionHealth()
  private var audio: VTLocalCapture?
  private var credentialsTask: Task<Void, Never>?
  private var bufferedStart: (AsyncStream<Data>, String, Double)?
  private(set) var trace = VTStartupTrace()
  var onTrace: (VTStartupTrace) -> Void = { _ in }
  private func record(_ stage: String, code: Int = 0) {
    if trace.record(stage, code: code) { onTrace(trace) }
  }
  private var ws: VTSpeechSocket?
  private var receiveTask: Task<Void, Never>?
  private var sendTask: Task<Void, Never>?
  private var watchdog: Task<Void, Never>?
  private var retryTask: Task<Void, Never>?
  private let relay = VTPCMRelay()
  private(set) var sessionID = ""
  private var captureID = ""
  private var afterStop: State?
  private var offset: Double = 0
  private var ids = Set<String>()
  private var profile = SpeechProfile()
  private var key = ""
  private var latestPartial = ""
  private var retryCount = 0
  private let permission: () async -> Bool
  private let makeCapture: () -> VTLocalCapture
  private let makeSocket: @MainActor (URLRequest) -> VTSpeechSocket
  private let now: () -> Date
  var onState: (State) -> Void = { _ in }
  var onStatus: (String) -> Void = { _ in }
  var onHealth: (VTRecognitionHealth) -> Void = { _ in }
  var onLevel: (Float) -> Void = { _ in }
  var onSentence: (Sentence, Bool, String) -> Void = { _, _, _ in }
  var onDraft: (VTDraft) -> Void = { _ in }
  var onAudio: (VTAudio) -> Void = { _ in }
  var duration: Double { audio?.duration() ?? 0 }
  init(
    permission: @escaping () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) },
    makeCapture: @escaping () -> VTLocalCapture = { VTSystemCapture() },
    makeSocket: (@MainActor (URLRequest) -> VTSpeechSocket)? = nil,
    now: @escaping () -> Date = Date.init
  ) {
    self.permission = permission
    self.makeCapture = makeCapture
    self.makeSocket = makeSocket ?? { VTURLSpeechSocket($0) }
    self.now = now
  }
  func start(folder: URL, offset: Double, profile: SpeechProfile, key: String) async throws {
    try await start(folder: folder, offset: offset, profile: profile, keyProvider: { key })
  }
  func start(
    folder: URL, offset: Double, profile: SpeechProfile, keyProvider: @escaping () async -> String
  ) async throws {
    guard state != .recording && state != .finishing && state != .starting else { return }
    trace = VTStartupTrace()
    record("requested")
    state = .starting
    onState(state)
    onStatus("正在检查麦克风权限…")
    guard await permission() else {
      record("permission_denied")
      state = .idle
      onState(state)
      throw VTError.message("请在系统设置中允许声迹VoiceTrace使用麦克风")
    }
    record("permission_ready")
    self.offset = offset
    self.profile = profile
    self.key = ""
    retryCount = 0
    captureID = UUID().uuidString
    latestPartial = ""
    let expectedCapture = captureID
    sessionID = UUID().uuidString
    var continuation: AsyncStream<Data>.Continuation!
    let startup = AsyncStream<Data>(bufferingPolicy: .bufferingOldest(160)) { continuation = $0 }
    bufferedStart = (startup, sessionID, offset)
    relay.install(continuation, token: sessionID)
    let firstPCM = VTOnce()
    let capture = makeCapture()
    audio = capture
    capture.onEvent = { stage, code in
      Task { @MainActor in
        guard self.captureID == expectedCapture else { return }
        self.record(stage, code: code)
        if stage == "engine_recovering" { self.onStatus("麦克风配置变化，正在自动恢复…") }
        if stage == "engine_recovered" { self.onStatus("麦克风已恢复，继续录音") }
      }
    }
    record("audio_starting")
    onStatus("正在启动麦克风…")
    do {
      try await capture.start(
        directory: folder, offset: offset,
        yield: { [relay] bytes in
          guard !bytes.isEmpty else { return }
          let dropped = relay.push(bytes)
          let first = firstPCM.claim()
          guard first || dropped != nil else { return }
          Task { @MainActor in
            guard self.captureID == expectedCapture else { return }
            if first { self.record("first_pcm") }
            if let token = dropped, self.sessionID == token {
              if self.key.isEmpty {
                self.bufferedStart = nil
                self.relay.finish()
                self.record("startup_buffer_full")
                self.onStatus("本地录音继续，识别正在等待凭据；开头片段可会后补转写")
              } else {
                self.connectionFailed("识别发送积压", retry: true)
              }
            }
          }
        },
        level: { value in
          Task { @MainActor in
            guard self.captureID == expectedCapture, self.state == .recording else { return }
            self.onLevel(value)
            if value > 0.04 { self.health.lastVoice = self.now() }
          }
        },
        interrupted: {
          Task { @MainActor in
            guard self.captureID == expectedCapture else { return }
            self.record("capture_failed")
            try? self.stop(pause: true)
            self.onStatus("麦克风自动恢复未成功，已暂停并保存；可查看启动诊断后继续")
          }
        },
        fail: {
          Task { @MainActor in
            guard self.captureID == expectedCapture else { return }
            self.record("capture_failed")
            try? self.stop(pause: true)
            self.onStatus("录音写盘失败，已暂停并保存；请检查磁盘并查看启动诊断")
          }
        })
    } catch {
      record("engine_start_failed", code: (error as NSError).code)
      audio = nil
      bufferedStart = nil
      relay.finish()
      self.key = ""
      state = .paused
      onState(state)
      throw error
    }
    state = .recording
    record("local_recording")
    onState(state)
    publish(.credentials, "本地录音已开始，正在读取识别服务凭据…")
    credentialsTask = Task {
      let secret = await keyProvider()
      guard !Task.isCancelled, self.captureID == expectedCapture, self.state == .recording else {
        return
      }
      self.key = secret
      self.record("credentials_ready")
      self.connect()
    }
  }
  private func publish(_ phase: VTRecognitionHealth.Phase, _ detail: String) {
    health.phase = phase
    health.detail = detail
    health.attempt = retryCount
    onHealth(health)
    onStatus(detail)
  }
  private func connect() {
    guard state == .recording else { return }
    guard !key.isEmpty else {
      record("credentials_unavailable")
      bufferedStart = nil
      relay.finish()
      publish(.offline, "正在本地录音；未配置语音密钥，可结束后补转写")
      return
    }
    let selected: SpeechProfile
    do { selected = try profile.validated() } catch {
      publish(.offline, "语音配置无效；本地录音继续，请结束后检查设置")
      return
    }
    let stream: AsyncStream<Data>
    let connectionOffset: Double
    if let initial = bufferedStart, initial.1 == sessionID {
      stream = initial.0
      connectionOffset = initial.2
      bufferedStart = nil
    } else {
      sessionID = UUID().uuidString
      connectionOffset = offset + duration
      var continuation: AsyncStream<Data>.Continuation!
      stream = AsyncStream<Data>(bufferingPolicy: .bufferingOldest(160)) { continuation = $0 }
      relay.install(continuation, token: sessionID)
    }
    let expected = sessionID
    ids = []
    latestPartial = ""
    var request = URLRequest(url: URL(string: "wss://\(selected.host)/api-ws/v1/inference")!)
    request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    request.setValue(selected.workspace, forHTTPHeaderField: "X-DashScope-WorkSpace")
    let socket = makeSocket(request)
    ws = socket
    socket.resume()
    health.connectedAt = nil
    health.lastResult = nil
    health.lastVoice = nil
    publish(.connecting, "本地录音已开始，正在连接实时识别…")
    watchdog = Task {
      try? await Task.sleep(nanoseconds: 20_000_000_000)
      if !Task.isCancelled, self.sessionID == expected {
        self.record("recognition_timeout", code: -1001)
        self.connectionFailed("识别连接超时", retry: true)
      }
    }
    receiveTask = Task {
      do {
        var parameters: [String: Any] = [
          "max_sentence_silence": selected.sentenceSilence ?? 800,
          "multi_threshold_mode_enabled": true,
        ]
        if selected.quietSpeech == true { parameters["speech_noise_threshold"] = -0.1 }
        try await socket.send(
          .string(
            String(
              decoding: Wire.json(
                Wire.command(
                  "run-task", id: expected, model: selected.realtimeModel, parameters: parameters)),
              as: UTF8.self)))
        while !Task.isCancelled {
          let message = try await socket.receive()
          let data: Data
          switch message {
          case .data(let d): data = d
          case .string(let s): data = Data(s.utf8)
          @unknown default: continue
          }
          guard self.sessionID == expected else { return }
          let obj = try Wire.object(data)
          let header = obj["header"] as? [String: Any] ?? [:]
          if let id = header["task_id"] as? String, id != expected { continue }
          switch header["event"] as? String {
          case "task-started":
            self.watchdog?.cancel()
            self.health.connectedAt = self.now()
            self.record("recognition_connected")
            self.publish(.live, "实时识别已连接；轻声时可在设置中调整灵敏度")
            self.sendTask = Task {
              do {
                for await bytes in stream {
                  try Task.checkCancellation()
                  try await socket.send(.data(bytes))
                }
                guard self.sessionID == expected else { return }
                try await socket.send(
                  .string(
                    String(
                      decoding: Wire.json(Wire.command("finish-task", id: expected)), as: UTF8.self)
                  ))
              } catch {
                if !Task.isCancelled, self.sessionID == expected {
                  self.record("recognition_send_error", code: (error as NSError).code)
                  self.connectionFailed("实时发送中断", retry: true)
                }
              }
            }
            self.watchdog = Task {
              while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if !Task.isCancelled, self.sessionID == expected { self.checkHealth() }
              }
            }
          case "result-generated":
            if let payload = obj["payload"] as? [String: Any],
              let output = payload["output"] as? [String: Any],
              let row = output["sentence"] as? [String: Any],
              let sentence = Wire.sentence(row, offset: connectionOffset)
            {
              let final = row["sentence_end"] as? Bool == true
              let id = "\(row["sentence_id"] ?? "")-\(row["begin_time"] ?? 0)"
              if !self.trace.events.contains(where: { $0.stage == "first_text" }) {
                self.record("first_text")
              }
              self.health.lastResult = self.now()
              self.onHealth(self.health)
              if !final || self.ids.insert(id).inserted {
                self.latestPartial = final ? "" : sentence.text
                self.onSentence(sentence, final, expected)
              }
            }
          case "task-finished":
            self.finishConnection()
            return
          case "task-failed":
            self.record(
              "recognition_rejected",
              code: (header["error_code"] as? NSNumber)?.intValue ?? Int(
                header["error_code"] as? String ?? "") ?? 0)
            self.connectionFailed("服务商拒绝识别任务，请检查地域、模型、额度和权限", retry: false)
            return
          default: break
          }
        }
      } catch {
        if !Task.isCancelled, self.sessionID == expected {
          self.record("recognition_connection_error", code: (error as NSError).code)
          self.connectionFailed("实时识别连接中断", retry: true)
        }
      }
    }
  }
  func checkHealth() {
    guard state == .recording else { return }
    if health.stalled(at: now()) {
      record("recognition_stalled")
      connectionFailed("持续检测到声音，但30秒没有返回文字", retry: true)
    }
  }
  func reconnect() {
    guard state == .recording, health.phase != .credentials else { return }
    retryTask?.cancel()
    preserveDraft()
    closeSocket()
    retryCount = 0
    connect()
  }
  private func preserveDraft() {
    if !latestPartial.isEmpty {
      onDraft(VTDraft(id: sessionID, text: latestPartial))
      latestPartial = ""
    }
  }
  private func connectionFailed(_ reason: String, retry: Bool) {
    preserveDraft()
    closeSocket()
    guard state == .recording else {
      finishConnection()
      return
    }
    guard retry, retryCount < 3 else {
      publish(.offline, reason + "；本地录音继续，可重连或会后补转写")
      return
    }
    retryCount += 1
    let delay: UInt64 = retryCount == 1 ? 1 : retryCount == 2 ? 3 : 8
    publish(.retrying, reason + "；\(delay)秒后第\(retryCount)次重连，本地录音继续。中断片段需会后补转写")
    retryTask = Task {
      try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
      if !Task.isCancelled, self.state == .recording { self.connect() }
    }
  }
  func stop(pause: Bool = false) throws {
    guard state == .recording else { return }
    retryTask?.cancel()
    credentialsTask?.cancel()
    bufferedStart = nil
    record(pause ? "audio_paused" : "audio_stopped")
    state = .finishing
    afterStop = pause ? .paused : .ended
    onState(state)
    do {
      if let (url, duration) = try audio?.stop() {
        onAudio(VTAudio(path: url.path, offset: offset, duration: duration))
      }
      audio = nil
      onLevel(0)
      relay.finish()
      if ws == nil {
        finishConnection()
        return
      }
      let expected = sessionID
      watchdog?.cancel()
      watchdog = Task {
        try? await Task.sleep(nanoseconds: 10_000_000_000)
        if !Task.isCancelled, self.sessionID == expected { self.finishConnection() }
      }
    } catch {
      state = .paused
      afterStop = nil
      preserveDraft()
      closeSocket()
      key = ""
      onState(state)
      throw error
    }
  }
  private func finishConnection() {
    preserveDraft()
    closeSocket()
    if let next = afterStop {
      afterStop = nil
      state = next
      key = ""
      captureID = ""
      onState(state)
      publish(.ended, "识别已结束；录音和已返回的文字保存在本机")
    } else if state == .recording {
      publish(.offline, "识别连接已结束，本地录音继续；可点击重新连接")
    }
  }
  private func closeSocket() {
    watchdog?.cancel()
    relay.finish()
    ws?.close()
    ws = nil
    receiveTask?.cancel()
    receiveTask = nil
    sendTask?.cancel()
    sendTask = nil
    sessionID = UUID().uuidString
  }
}
