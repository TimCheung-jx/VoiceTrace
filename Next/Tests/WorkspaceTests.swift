import Foundation

@main struct WorkspaceChecks {
  @MainActor static func main() async throws {
    let base = URL(fileURLWithPath: CommandLine.arguments[1])
    let response = base.appendingPathComponent("Next/Fixtures/response.json")
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
      "vt-next-workspace-" + UUID().uuidString)
    setenv("VTNEXT_DATA", root.path, 1)
    setenv("VTNEXT_QA", "1", 1)
    let w = VTWorkspace()
    w.loadFixture(response)
    while w.busy { await Task.yield() }
    if w.document.analysis.graph.nodes.count != 9
      || w.document.analysis.states["graph"]?.phase != .ready
    {
      print("诊断：", w.status, w.issue, w.saved, w.document.analysis.states)
      fflush(stdout)
    }
    precondition(
      w.document.analysis.graph.nodes.count == 9
        && w.document.analysis.states["graph"]?.phase == .ready)
    var cachedCalls = 0
    let existing = w.document.analysis.graph
    w.analyze(sections: Set(VTSection.allCases), model: "fictional", scope: "fictional") { _ in
      cachedCalls += 1
      throw VTError.message("同一原文应使用已经校验的缓存")
    }
    while w.busy { await Task.yield() }
    precondition(
      cachedCalls == 0 && w.document.analysis.graph == existing
        && w.document.analysis.states["graph"]?.phase == .ready)
    let id = w.document.id
    let task = w.document.analysis.tasks[0].id
    w.toggleTask(task)
    let next = VTWorkspace()
    precondition(next.document.id == id && next.document.completed.contains(task))
    let before = next.document.analysis
    next.analyze(sections: [.graph], model: "broken", scope: "bad") { _ in "invalid" }
    while next.busy { await Task.yield() }
    precondition(
      next.document.analysis.graph == before.graph
        && next.document.analysis.states["graph"]?.phase == .failed)
    var gate: CheckedContinuation<Void, Never>?
    next.analyze(sections: Set(VTSection.allCases), model: "delayed", scope: "delayed") { _ in
      await withCheckedContinuation { gate = $0 }
      return try String(contentsOf: response, encoding: .utf8)
    }
    while gate == nil { await Task.yield() }
    let lockedID = next.document.id
    next.create()
    precondition(next.document.id == lockedID)
    next.document.utterances.append(
      VTUtterance(id: "u-new", start: 180, end: 190, speakerID: nil, text: "虚构新增发言"))
    next.document.invalidate()
    gate?.resume()
    while next.busy { await Task.yield() }
    precondition(next.document.analysis.states["graph"]?.phase == .stale)
    next.document.protected.insert("graph")
    let protectedGraph = next.document.analysis.graph
    next.analyze(sections: Set(VTSection.allCases), model: "fictional", scope: "protected") { _ in
      try String(contentsOf: response, encoding: .utf8)
    }
    while next.busy { await Task.yield() }
    precondition(next.document.analysis.graph == protectedGraph)
    next.document.protected = []
    next.save()
    let repo = next.repository!
    // 模拟异常进程留下的PCM，恢复不删除原件、不上传。
    let folder = try repo.audioFolder(id)
    let pcm = folder.appendingPathComponent("audio-fictional.pcm")
    try Data(repeating: 0, count: 32000).write(to: pcm)
    try Data("{\"offset\":200}".utf8).write(to: pcm.appendingPathExtension("capture.json"))
    let candidates = try VTRecovery.scan(repository: repo)
    precondition(candidates.count == 1)
    // 上一次恢复只写出文件头时，再次恢复另建完整文件，不覆盖或删除旧残片。
    try Data([1, 2, 3]).write(to: candidates[0].target)
    let recovered = try candidates[0].recover()
    precondition(
      recovered.offset == 200 && recovered.duration == 1
        && FileManager.default.fileExists(atPath: pcm.path))
    next.document.audio.append(recovered)
    next.save()
    let afterRecovery = try VTRecovery.scan(repository: repo)
    precondition(afterRecovery.isEmpty)
    // 旧资料导入复制原件；再导入不会重复创建文档。
    let legacy = root.appendingPathComponent("fictional-legacy")
    var old = Meeting()
    old.title = "虚构旧版会议"
    old.sentences = [Sentence(start: 0, end: 10, text: "虚构发言", speaker: "发言人1")]
    old.notes = "保留旧笔记"
    try MeetingDisk.save(old, root: legacy)
    next.importLegacy(legacy)
    let total = next.documents.count
    next.importLegacy(legacy)
    precondition(next.documents.count == total)
    precondition(
      next.documents.contains { $0.notes == "保留旧笔记" }
        && FileManager.default.fileExists(
          atPath: legacy.appendingPathComponent(old.id).appendingPathComponent("meeting.json").path)
    )
    let restored = next.documents.first { $0.id == id }!
    next.moveToTrash([id])
    precondition(next.documents.first { $0.id == id }!.trashed)
    next.moveToTrash([id], restore: true)
    precondition(!next.documents.first { $0.id == id }!.trashed)
    precondition(restored.analysis.graph.nodes.count == 9)
    next.create()
    next.document.title = "虚构声音身份测试"
    let speechA = Wire.sentence(
      ["text": "虚构发言甲", "begin_time": 0, "end_time": 1000, "speaker_id": 0], offset: 0)!
    let speechB = Wire.sentence(
      ["text": "虚构发言乙", "begin_time": 1000, "end_time": 2000, "speaker_id": 1], offset: 0)!
    next.recorder.onSentence(speechA, true, "segment-test")
    next.recorder.onSentence(speechB, true, "segment-test")
    let identityA = next.document.utterances[0].speakerID!
    precondition(next.document.speaker(identityA) == "发言人1" && next.document.speakers.count == 2)
    next.document.audio.append(VTAudio(path: "fictional-not-read.wav", offset: 0, duration: 2))
    next.recorder.onSentence(speechA, true, "segment-test")
    precondition(
      next.document.utterances.last!.speakerID == identityA && next.document.speakers.count == 2)
    next.recorder.onSentence(Sentence(start: 3, end: 4, text: "尚未区分的声音"), true, "segment-test")
    precondition(
      next.document.utterances.last!.speakerID == nil && next.document.speakers.count == 2)
    next.document.analysis.graph.nodes = [
      VTNode(
        id: "speaker-node", kind: .position, title: "原文观点", detail: "虚构观点", speakerID: identityA,
        sourceIDs: [next.document.utterances[0].id])
    ]
    precondition(next.renameSpeaker(identityA, name: "张经理"))
    precondition(
      next.document.utterances.filter { $0.speakerID == identityA }.count == 2
        && next.document.speaker(next.document.analysis.graph.nodes[0].speakerID) == "张经理")
    let reopenedIdentity = VTWorkspace()
    precondition(reopenedIdentity.document.speakers.first { $0.id == identityA }?.name == "张经理")
    let identityHistory = try reopenedIdentity.repository!.history(reopenedIdentity.document.id)
    precondition(
      identityHistory.contains { $0.1 == "统一修改发言人身份" && $0.2.speaker(identityA) == "发言人1" })
    next.partial = "虚构临时文字"
    next.answer = "虚构上一场回答"
    next.question = "虚构问题"
    next.create()
    precondition(next.partial.isEmpty && next.question.isEmpty && next.answer.isEmpty)
    next.partial = "虚构临时文字"
    next.open(restored)
    precondition(next.partial.isEmpty)
    next.recorder.onDraft(VTDraft(id: "fictional-segment", text: "虚构未定稿"))
    precondition(next.partial.isEmpty && next.document.unfinished?.first?.text == "虚构未定稿")
    let documentID = next.document.id
    next.renameMeeting(documentID, title: "虚构重命名会议")
    let named = try next.repository!.load(documentID)!
    precondition(named.title == "虚构重命名会议" && named.utterances == restored.utterances)
    let renameOther = next.documents.first { $0.id != documentID }!.id
    next.renameMeeting(renameOther, title: "虚构列表内编辑")
    precondition(
      next.document.id == documentID
        && next.documents.first { $0.id == renameOther }!.title == "虚构列表内编辑")
    let batch = Set([documentID, renameOther])
    next.moveToTrash(batch)
    precondition(next.documents.filter { batch.contains($0.id) && $0.trashed }.count == 2)
    next.moveToTrash(batch, restore: true)
    precondition(next.documents.filter { batch.contains($0.id) && !$0.trashed }.count == 2)
    next.question = "虚构旧会议问题"
    var replyGate: CheckedContinuation<String, Never>?
    let questionRun = Task {
      await next.ask(call: { _, _ in await withCheckedContinuation { replyGate = $0 } })
    }
    try await eventually { replyGate != nil }
    precondition(next.asking && !next.busy)
    next.create()
    replyGate?.resume(returning: "不应进入新会议的回答")
    await questionRun.value
    precondition(next.answer.isEmpty && !next.asking && next.question.isEmpty)
    print("PASS: 问答不锁住会议切换；切换后取消旧请求，迟到回答不进入新会议。")
    next.open(restored)
    next.question = "虚构第一条问题"
    var chatGate: CheckedContinuation<String, Never>?
    let chatRun = Task {
      await next.ask(call: { _, _ in await withCheckedContinuation { chatGate = $0 } })
    }
    try await eventually { chatGate != nil }
    precondition(next.question.isEmpty && next.document.conversation?.last?.question == "虚构第一条问题")
    next.question = "虚构下一条草稿"
    chatGate?.resume(returning: "**虚构回答一**")
    await chatRun.value
    precondition(next.question == "虚构下一条草稿" && next.document.conversation?.last?.phase == .answered)
    await next.ask(call: { document, _ in
      precondition(document.followup("追问").contains("虚构回答一"))
      return "虚构回答二"
    })
    precondition(next.question.isEmpty && next.document.conversation?.suffix(2).count == 2)
    let kept = next.document.unfinished
    next.dismissDraftsNotice()
    let chatReload = try next.repository!.load(next.document.id)!
    precondition(
      chatReload.conversation?.last?.answer == "虚构回答二" && chatReload.draftsNoticeDismissed == true
        && chatReload.unfinished == kept)
    try await checkLocalFirst(root)
    try await checkWorkspaceLocalFirst()
    print("PASS: 提交后立即清空输入，连续问答保留及重开，回答不覆盖下一条草稿；未定稿提示关闭后原文保留。")
    try await checkRecorderRecovery(root)
    print("PASS: 新建/切换清理临时稿；未定稿持久化；列表内改名不切换会议；批量删除/恢复。")
    print("PASS: 识别结果边界的两个声音→发言人1/2；结束后尾句身份不漂移；无分离结果不造编号；统一命名同步及重开、历史保留。")
    print(
      "PASS: 工作台真实处理入口→API响应模拟→持久化重开；任务状态；错误保留；处理中切换保护；增量原文失效；人工保护；PCM异常恢复；旧版迁移幂等与原件保留；最近删除恢复。未联网/未调用麦克风或真实密钥。"
    )
  }
}

final class FakeLocalCapture: VTLocalCapture {
  var onEvent: ((String, Int) -> Void)?
  var push: ((Data) -> Void)?
  var meter: ((Float) -> Void)?
  var stopped = false
  var seconds: Double = 0
  func start(
    directory: URL, offset: Double, yield: @escaping (Data) -> Void,
    level: @escaping (Float) -> Void, interrupted: @escaping () -> Void, fail: @escaping () -> Void
  ) async throws {
    stopped = false
    push = yield
    meter = level
  }
  func duration() -> Double { seconds }
  func stop() throws -> (URL, Double)? {
    stopped = true
    return (URL(fileURLWithPath: "/private/tmp/fictional-capture.wav"), seconds)
  }
}
@MainActor final class FakeSpeechSocket: VTSpeechSocket {
  var sent: [URLSessionWebSocketTask.Message] = []
  var queued: [URLSessionWebSocketTask.Message] = []
  var pending: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?
  var closed = false
  func resume() {}
  func send(_ message: URLSessionWebSocketTask.Message) async throws { sent.append(message) }
  func receive() async throws -> URLSessionWebSocketTask.Message {
    if !queued.isEmpty { return queued.removeFirst() }
    return try await withCheckedThrowingContinuation { pending = $0 }
  }
  func close() {
    closed = true
    let p = pending
    pending = nil
    p?.resume(throwing: CancellationError())
  }
  func event(_ name: String, id: String, row: [String: Any]? = nil) throws {
    var event: [String: Any] = ["header": ["event": name, "task_id": id]]
    if let row = row { event["payload"] = ["output": ["sentence": row]] }
    let message = URLSessionWebSocketTask.Message.data(try Wire.json(event))
    if let p = pending {
      pending = nil
      p.resume(returning: message)
    } else {
      queued.append(message)
    }
  }
}
@MainActor func eventually(_ predicate: () -> Bool) async throws {
  for _ in 0..<1500 {
    if predicate() { return }
    try await Task.sleep(nanoseconds: 1_000_000)
  }
  throw VTError.message("虚构事件未在预期时间内完成")
}
@MainActor func checkRecorderRecovery(_ root: URL) async throws {
  let capture = FakeLocalCapture()
  var sockets: [FakeSpeechSocket] = []
  var clock = Date(timeIntervalSince1970: 1000)
  let r = VTRecorder(
    permission: { true }, makeCapture: { capture },
    makeSocket: { _ in
      let s = FakeSpeechSocket()
      sockets.append(s)
      return s
    }, now: { clock })
  var profile = SpeechProfile()
  profile.workspace = "fictional-workspace"
  profile.quietSpeech = true
  var text: [String] = []
  var drafts: [VTDraft] = []
  var audio: [VTAudio] = []
  r.onSentence = { s, _, _ in text.append(s.text) }
  r.onDraft = { drafts.append($0) }
  r.onAudio = { audio.append($0) }
  try await r.start(folder: root, offset: 10, profile: profile, key: "fictional-only")
  try await eventually { sockets.count == 1 && !sockets[0].sent.isEmpty }
  let old = sockets[0]
  let oldID = r.sessionID
  if case .string(let command) = old.sent[0] {
    let obj = try Wire.object(Data(command.utf8))
    let parameters = (obj["payload"] as! [String: Any])["parameters"] as! [String: Any]
    precondition(
      parameters["max_sentence_silence"] as? Int == 800
        && parameters["speech_noise_threshold"] as? Double == -0.1)
  } else {
    preconditionFailure("未发送启动命令")
  }
  try old.event("task-started", id: oldID)
  try await eventually { r.health.phase == .live }
  capture.seconds = 2
  capture.push?(Data([1, 2]))
  try await eventually { old.sent.count == 2 }
  try old.event(
    "result-generated", id: oldID,
    row: ["text": "虚构尚未定稿", "begin_time": 0, "end_time": 1000, "sentence_end": false])
  try await eventually { !text.isEmpty }
  clock = clock.addingTimeInterval(31)
  capture.meter?(0.5)
  try await Task.sleep(nanoseconds: 5_000_000)
  r.checkHealth()
  precondition(
    r.health.phase == .retrying && r.state == .recording && !capture.stopped
      && drafts.first?.text == "虚构尚未定稿")
  try await eventually { sockets.count == 2 && !sockets[1].sent.isEmpty }
  let automatic = sockets[1]
  try automatic.event("task-started", id: r.sessionID)
  try await eventually { r.health.phase == .live }
  precondition(!capture.stopped)
  r.reconnect()
  try await eventually { sockets.count == 3 && !sockets[2].sent.isEmpty }
  let fresh = sockets[2]
  let newID = r.sessionID
  precondition(old.closed && oldID != newID)
  try fresh.event("task-started", id: newID)
  try await eventually { r.health.phase == .live }
  try fresh.event(
    "result-generated", id: oldID, row: ["text": "不应接收的旧任务", "begin_time": 0, "sentence_end": true])
  try fresh.event(
    "result-generated", id: newID, row: ["text": "虚构重连后新句", "begin_time": 0, "sentence_end": true])
  try await eventually { text.contains("虚构重连后新句") }
  precondition(!text.contains("不应接收的旧任务"))
  capture.push?(Data([3, 4]))
  try await eventually { fresh.sent.count >= 2 }
  capture.seconds = 4
  try r.stop()
  try fresh.event("task-finished", id: newID)
  try await eventually { r.state == .ended }
  precondition(capture.stopped && audio.count == 1 && audio[0].duration == 4)
  try await r.start(folder: root, offset: 14, profile: profile, key: "")
  try await eventually { r.health.phase == .offline }
  precondition(r.state == .recording && sockets.count == 3)
  try r.stop()
  precondition(r.state == .ended && audio.count == 2)
  print("PASS: 模拟有声无回字→自动重连建立新连接；本地采集不中断；手动重连接续音频；旧任务隔离；结束保存及再次录音。未访问真实麦克风、网络或密钥。")
}

@MainActor func checkLocalFirst(_ root: URL) async throws {
  let capture = FakeLocalCapture()
  var secretGate: CheckedContinuation<String, Never>?
  var sockets: [FakeSpeechSocket] = []
  let r = VTRecorder(
    permission: { true }, makeCapture: { capture },
    makeSocket: { _ in
      let s = FakeSpeechSocket()
      sockets.append(s)
      return s
    })
  var profile = SpeechProfile()
  profile.workspace = "fictional-workspace"
  try await r.start(
    folder: root, offset: 0, profile: profile,
    keyProvider: { await withCheckedContinuation { secretGate = $0 } })
  try await eventually { secretGate != nil }
  precondition(r.state == .recording && capture.push != nil && sockets.isEmpty)
  capture.push?(Data([1, 2, 3, 4]))
  try await eventually { r.trace.events.contains { $0.stage == "first_pcm" } }
  // 设备恢复事件不会直接把录音状态变为暂停。
  capture.onEvent?("configuration_stable", 0)
  capture.onEvent?("engine_recovering", 0)
  capture.onEvent?("engine_recovered", 0)
  try await eventually { r.trace.events.contains { $0.stage == "engine_recovered" } }
  precondition(r.state == .recording && !capture.stopped)
  secretGate?.resume(returning: "fictional-only")
  try await eventually { sockets.count == 1 && !sockets[0].sent.isEmpty }
  let id = r.sessionID
  try sockets[0].event("task-started", id: id)
  try await eventually { sockets[0].sent.count >= 2 }
  if case .data(let bytes) = sockets[0].sent[1] {
    precondition(bytes == Data([1, 2, 3, 4]))
  } else {
    preconditionFailure("启动音频缓冲未发送")
  }
  try r.stop(pause: true)
  try sockets[0].event("task-finished", id: id)
  try await eventually { r.state == .paused }
  var delayed: CheckedContinuation<String, Never>?
  try await r.start(
    folder: root, offset: 0, profile: profile,
    keyProvider: { await withCheckedContinuation { delayed = $0 } })
  try await eventually { delayed != nil }
  try r.stop()
  delayed?.resume(returning: "fictional-only")
  try await Task.sleep(nanoseconds: 10_000_000)
  precondition(r.state == .ended && sockets.count == 1)
  let json = String(decoding: try JSONEncoder().encode(r.trace), as: UTF8.self)
  precondition(!json.contains("fictional-only") && !json.contains("fictional-workspace"))
  print("PASS: 凭据未返回时已本地录音；开头音频缓冲接续发送；恢复通知不闪停；暂停继续及结束后迟到凭据不连接；诊断无密钥和配置内容。")
}

@MainActor func checkWorkspaceLocalFirst() async throws {
  let capture = FakeLocalCapture()
  let recorder = VTRecorder(
    permission: { true }, makeCapture: { capture },
    makeSocket: { _ in preconditionFailure("等待凭据时不应连接网络") })
  var keyGate: CheckedContinuation<String, Never>?
  let w = VTWorkspace(
    recorder: recorder, credentialReader: { _ in await withCheckedContinuation { keyGate = $0 } })
  w.finalAutomatic = false
  await w.start()
  try await eventually { keyGate != nil }
  precondition(w.recording && !w.preparing && capture.push != nil)
  capture.seconds = 2
  capture.push?(Data([0, 0, 0, 0]))
  try await eventually { w.startupTrace.events.contains { $0.stage == "first_pcm" } }
  w.stop()
  keyGate?.resume(returning: "")
  try await eventually { w.recordState == "已结束" }
  let path = w.root.appendingPathComponent("diagnostics/startup-" + w.startupTrace.id + ".json")
  try await eventually {
    guard let data = try? Data(contentsOf: path),
      let trace = try? JSONDecoder().decode(VTStartupTrace.self, from: data)
    else { return false }
    return trace.events.contains { $0.stage == "audio_stopped" }
  }
  print("PASS: 工作台实际开始入口先录音后等待凭据，启动指示退出；诊断异步写盘保留完整结束阶段。")
}
