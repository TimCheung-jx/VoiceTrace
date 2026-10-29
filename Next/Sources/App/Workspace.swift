import AVFoundation
import AppKit
import SwiftUI

@MainActor final class VTWorkspace: ObservableObject {
  @Published var documents: [VTDocument] = []
  @Published var document = VTDocument()
  @Published var page = "总览"
  @Published var search = ""
  @Published var showTrash = false
  @Published var selectedNode: String?
  @Published var sourceIDs: [String] = []
  @Published var showSettings = false
  @Published var showHistory = false
  @Published var showSpeakers = false
  @Published var showAsk = false
  @Published var asking = false
  @Published var showStartupInfo = false
  @Published var showDrafts = false
  @Published var startupTrace = VTStartupTrace()
  @Published var issue = ""
  @Published var status = "本地资料库"
  @Published var busy = false
  @Published var recording = false
  @Published var preparing = false
  @Published var recordState = "未开始"
  @Published var partial = ""
  @Published var level: Float = 0
  @Published var recognition = VTRecognitionHealth()
  @Published var saved = true
  @Published var settings: SettingsFile
  @Published var automatic = true
  @Published var finalAutomatic = true
  @Published var jsonMode = true
  @Published var filterSpeaker: String? = nil
  @Published var onlyDisputes = false
  @Published var question = ""
  @Published var answer = ""
  let repository: VTRepository?
  let root: URL
  let recorder: VTRecorder
  private let credentialReader: (String) async -> String
  private var loop: Task<Void, Never>?
  private var generation: Task<Void, Never>?
  private var questionTask: Task<String, Error>?
  private var questionToken = UUID()
  private var activeQuestionID: String?
  private var player: AVAudioPlayer?
  private let diagnosticQueue = DispatchQueue(label: "org.voicetrace.diagnostics", qos: .utility)
  private var selectionEpoch = 0
  var lastGenerated = ""
  var history: [(String, String, VTDocument)] = []
  var locked: Bool {
    busy || recording || preparing || (recordState == "正在收尾" || recordState == "正在启动麦克风")
  }
  var visible: [VTDocument] {
    documents.filter {
      $0.trashed == showTrash
        && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
    }.sorted { $0.created > $1.created }
  }
  init(
    recorder suppliedRecorder: VTRecorder? = nil,
    credentialReader: ((String) async -> String)? = nil
  ) {
    self.recorder = suppliedRecorder ?? VTRecorder()
    self.credentialReader =
      credentialReader ?? { account in
        await Task.detached(priority: .userInitiated) { Vault.read(account) }.value
      }

    let env = ProcessInfo.processInfo.environment
    root =
      env["VTNEXT_DATA"].map { URL(fileURLWithPath: $0) }
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(AppIdentity.personal ? "VoiceTrace Next Personal" : "VoiceTrace Next")
    let defaults = UserDefaults.standard
    if env["VTNEXT_QA"] == "1" {
      settings = SettingsFile.fresh()
    } else if let data = defaults.data(forKey: "profiles"),
      let saved = try? JSONDecoder().decode(SettingsFile.self, from: data), !saved.speech.isEmpty,
      !saved.texts.isEmpty
    {
      settings = saved
    } else if AppIdentity.personal && env["VTNEXT_QA"] != "1" {
      settings =
        UserDefaults(suiteName: "com.tim.tingjian").map { SettingsFile.load($0) }
        ?? SettingsFile.fresh()
    } else {
      settings = SettingsFile.fresh()
    }
    jsonMode = defaults.object(forKey: "jsonMode") as? Bool ?? true
    automatic = defaults.object(forKey: "liveAnalysis") as? Bool ?? true
    finalAutomatic = defaults.object(forKey: "finalAnalysis") as? Bool ?? true
    do { repository = try VTRepository(root: root) } catch {
      repository = nil
      issue = "资料库无法打开，暂勿录音；请检查目录权限和磁盘空间"
    }
    if let files = try? FileManager.default.contentsOfDirectory(
      at: root.appendingPathComponent("diagnostics"),
      includingPropertiesForKeys: [.contentModificationDateKey]),
      let latest = files.filter({
        $0.lastPathComponent.hasPrefix("startup-") && $0.pathExtension == "json"
      }).max(by: {
        ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
          ?? .distantPast)
          < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast)
      }),
      let data = try? Data(contentsOf: latest),
      let trace = try? JSONDecoder().decode(VTStartupTrace.self, from: data)
    {
      startupTrace = trace
    }
    refresh()
    for var doc in documents {
      var changed = false
      for key in doc.analysis.states.keys where doc.analysis.states[key]?.phase == .working {
        doc.analysis.states[key]?.phase = .failed
        doc.analysis.states[key]?.message = "上次整理中断，已有成果保留，可重新整理"
        changed = true
      }
      if var chat = doc.conversation {
        for index in chat.indices where chat[index].phase == .waiting {
          chat[index].phase = .cancelled
          changed = true
        }
        doc.conversation = chat
      }
      if ["录音中", "正在收尾", "正在启动麦克风"].contains(doc.capture) {
        doc.capture = "异常中断，待核对"
        changed = true
      }
      if changed { try? repository?.save(doc) }
    }
    refresh()
    if let first = documents.first(where: { !$0.trashed }) {
      document = first
      recordState = first.capture
    }
    recorder.onState = { [weak self] state in
      guard let self = self else { return }
      self.recordState = state.rawValue
      self.recording = state == .recording
      self.document.capture = state.rawValue
      if state != .starting { self.save() }
      if state == .paused || state == .ended { self.persistStartupTrace(self.recorder.trace) }
    }
    recorder.onTrace = { [weak self] trace in
      self?.startupTrace = trace
      if trace.events.last?.stage == "first_pcm" || trace.hasFailure {
        self?.persistStartupTrace(trace)
      }
    }
    recorder.onStatus = { [weak self] text in self?.status = text }
    recorder.onHealth = { [weak self] health in self?.recognition = health }
    recorder.onDraft = { [weak self] draft in
      guard let self = self else { return }
      self.document.unfinished =
        (self.document.unfinished ?? []).filter { $0.id != draft.id } + [draft]
      self.partial = ""
      self.save()
    }
    recorder.onLevel = { [weak self] value in self?.level = value }
    recorder.onAudio = { [weak self] audio in
      self?.document.audio.append(audio)
      self?.save()
    }
    recorder.onSentence = { [weak self] sentence, final, segment in
      guard let self = self else { return }
      if final {
        let speakerID: String?
        if sentence.speaker.contains("区分") {
          speakerID = nil
        } else {
          speakerID = self.document.registerVoice(track: segment + "|" + sentence.speaker)
        }
        self.document.utterances.append(
          VTUtterance(
            id: UUID().uuidString, start: sentence.start, end: sentence.end, speakerID: speakerID,
            text: sentence.text))
        self.document.invalidate()
        self.partial = ""
        self.save()
      } else {
        self.partial = sentence.text
      }
    }
  }
  func renameSpeaker(_ id: String, name: String) -> Bool {
    guard !locked, saved else { return false }
    let before = document
    do {
      try document.nameSpeaker(id, name: name)
      if save(reason: "统一修改发言人身份") {
        status = "发言人标签已统一更新；重新整理可更新正文中的称呼"
        return true
      }
      document = before
    } catch {
      issue = error.localizedDescription
      document = before
    }
    return false
  }
  func recoverRecordings() {
    guard !locked, let repository = repository else { return }
    do {
      let items = try VTRecovery.scan(repository: repository)
      var count = 0
      for item in items {
        guard var doc = try repository.load(item.documentID) else { continue }
        let audio = try item.recover()
        if !doc.audio.contains(where: { $0.path == audio.path }) {
          doc.audio.append(audio)
          doc.capture = "异常中断后已恢复"
          try repository.save(doc, reason: "恢复录音前版本")
          count += 1
          if document.id == doc.id { document = doc }
        }
      }
      refresh()
      status = "已恢复 \(count) 段录音；原始PCM保留，尚未上传"
    } catch { issue = "恢复未完成。原始录音保留，请检查磁盘空间和目录权限。" }
  }
  func refresh() {
    do { documents = try repository?.list() ?? [] } catch { issue = "读取会议列表失败，请检查本地资料库" }
  }
  @discardableResult func save(reason: String? = nil) -> Bool {
    if document.title == "未命名会议" && document.utterances.isEmpty && document.audio.isEmpty
      && document.notes.isEmpty
    {
      return true
    }
    guard let repository = repository else {
      saved = false
      return false
    }
    do {
      try repository.save(document, reason: reason)
      saved = true
      documents.removeAll { $0.id == document.id }
      documents.append(document)
      return true
    } catch {
      saved = false
      issue = "本地保存失败。窗口中内容仍保留，请导出备份，暂勿退出。"
      return false
    }
  }
  func create() {
    guard !locked, saved else { return }
    resetTransient()
    document = VTDocument()
    let f = DateFormatter()
    f.dateFormat = "MM月dd日 HH:mm"
    document.title = "会议 " + f.string(from: Date())
    page = "原文"
    sourceIDs = []
    selectedNode = nil
    recordState = "未开始"
    selectionEpoch += 1
    save()
  }
  func open(_ item: VTDocument) {
    guard !locked, saved else { return }
    resetTransient()
    document = item
    page = "总览"
    selectedNode = nil
    filterSpeaker = nil
    onlyDisputes = false
    sourceIDs = []
    recordState = item.capture
    selectionEpoch += 1
    answer = ""
    lastGenerated = ""
  }
  private func resetTransient() {
    cancelQuestion()
    player?.stop()
    partial = ""
    level = 0
    recognition = VTRecognitionHealth()
    question = ""
    answer = ""
    sourceIDs = []
    selectedNode = nil
    filterSpeaker = nil
    onlyDisputes = false
    lastGenerated = ""
  }
  func renameMeeting(_ id: String, title: String) {
    guard !locked, saved, var item = documents.first(where: { $0.id == id }) else { return }
    let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty, clean.count <= 160 else {
      issue = "会议名称应为1至160字"
      return
    }
    item.title = clean
    do {
      try repository?.save(item, reason: "重命名会议")
      if document.id == id { document = item }
      refresh()
      status = "会议已重命名"
    } catch { issue = "重命名未能保存，请重试" }
  }
  func select(_ node: VTNode) {
    selectedNode = node.id
    sourceIDs = node.sourceIDs
  }
  func reveal(_ ids: [String]) { sourceIDs = ids }
  func play(_ row: VTUtterance) {
    guard
      let audio = document.audio.last(where: {
        $0.offset <= row.start && row.start < $0.offset + $0.duration
      })
    else {
      status = "此片段未关联录音；可查看原文"
      return
    }
    do {
      player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: audio.path))
      player?.currentTime = max(0, row.start - audio.offset)
      player?.play()
    } catch { issue = "无法播放录音，请检查文件位置" }
  }
  func toggleTask(_ id: String) {
    let old = document
    document.completed.formSymmetricDifference([id])
    if !save() { document = old }
  }
  func moveToTrash(_ ids: Set<String>, restore: Bool = false) {
    guard !locked, saved else { return }
    do {
      for item in documents where ids.contains(item.id) {
        var next = item
        next.trashed = !restore
        try repository?.save(next, reason: restore ? "恢复会议" : "移入最近删除")
        if document.id == next.id { document = next }
      }
      refresh()
    } catch { issue = "部分会议未能保存，请检查列表后重试" }
  }
  func start() async {
    guard !locked, saved, repository != nil else { return }
    if document.title == "未命名会议" { create() }
    preparing = true
    defer { preparing = false }
    player?.stop()
    partial = ""
    do {
      let folder = try repository!.audioFolder(document.id)
      let account = settings.activeSpeech.keyAccount
      let loader = credentialReader
      try await recorder.start(
        folder: folder, offset: document.audio.reduce(0, { $0 + $1.duration }),
        profile: settings.activeSpeech, keyProvider: { await loader(account) })
      page = "原文"
      loop?.cancel()
      loop = Task {
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: 45_000_000_000)
          if !Task.isCancelled, self.automatic, self.recording, !self.busy,
            self.lastGenerated != self.document.revision
          {
            self.generate()
          }
        }
      }
    } catch { issue = error.localizedDescription }
  }
  func stop(pause: Bool = false) {
    do {
      try recorder.stop(pause: pause)
      loop?.cancel()
      status = pause ? "已暂停并保存录音" : "录音已保存；正在等待最后文字"
      if !pause && finalAutomatic {
        let id = document.id
        Task {
          while self.busy || self.recordState == "正在收尾" {
            try? await Task.sleep(nanoseconds: 300_000_000)
          }
          if !self.recording, self.document.id == id { self.generate() }
        }
      }
    } catch { issue = "录音保存失败，请保留应用并检查磁盘空间" }
  }
  func generate(sections: Set<VTSection> = Set(VTSection.allCases)) {
    guard !busy, !document.utterances.isEmpty, saved else { return }
    let key = Vault.read(settings.activeText.keyAccount)
    guard !key.isEmpty else {
      issue = "请在设置中保存整理服务的 API Key"
      showSettings = true
      return
    }
    let text = settings.activeText
    let config = VTModelConfig(baseURL: text.baseURL, model: text.model, jsonMode: jsonMode)
    analyze(sections: sections, model: text.model, scope: text.id + text.model + text.baseURL) {
      doc in
      try await VTModelClient.request(
        document: doc, config: config, key: key,
        transport: { request in
          let (data, response) = try await Network.shared.session.data(for: request)
          return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        })
    }
  }
  // 与真实服务和模拟服务共用的处理入口。
  func analyze(
    sections: Set<VTSection>, model: String, scope: String,
    call: @escaping (VTDocument) async throws -> String
  ) {
    guard !busy, !document.utterances.isEmpty, saved else { return }
    let snapshot = document
    let old = snapshot.analysis
    let id = snapshot.id
    busy = true
    status = "正在按原文整理…"
    for section in sections where !document.protected.contains(section.rawValue) {
      document.analysis.states[section.rawValue] = VTArtifactState(
        phase: .working, message: "", updated: nil, revision: snapshot.revision)
    }
    guard save(reason: "整理前自动备份") else {
      busy = false
      return
    }
    generation = Task {
      do {
        let chunks = try VTAnalyzer.chunks(snapshot)
        var parts: [VTAnalysis] = []
        for (index, chunk) in chunks.enumerated() {
          try Task.checkCancellation()
          self.status = "整理片段 \(index+1)/\(chunks.count)"
          let fingerprint = vtID("schema1|" + scope + "|" + (try VTAnalyzer.source(chunk)))
          if let cached = self.document.cache[fingerprint],
            sections.allSatisfy({ cached.states[$0.rawValue]?.phase == .ready })
          {
            parts.append(cached)
            continue
          }
          let raw = try await call(chunk)
          try Task.checkCancellation()
          var parsed = try VTAnalyzer.ingest(raw, document: chunk, model: model)
          // 仅重试有问题的成果；图形是分歧引用的基础，一并校验。
          let failed = Set(sections.filter { parsed.states[$0.rawValue]?.phase == .failed })
          if !failed.isEmpty {
            self.status = "部分结果正在重新校验…"
            let retry = try await call(chunk)
            try Task.checkCancellation()
            parsed = try VTAnalyzer.ingest(
              retry, document: chunk, previous: parsed, model: model,
              sections: failed.union(failed.contains(.disputes) ? [.graph] : []))
          }
          parts.append(parsed)
          self.document.cache[fingerprint] = parsed
        }
        try Task.checkCancellation()
        guard self.document.id == id else { return }
        let merged = VTAnalyzer.merge(parts, document: snapshot, previous: old)
        for section in sections where !self.document.protected.contains(section.rawValue) {
          switch section {
          case .minutes: self.document.analysis.minutes = merged.minutes
          case .graph: self.document.analysis.graph = merged.graph
          case .disputes: self.document.analysis.disputes = merged.disputes
          case .tasks: self.document.analysis.tasks = merged.tasks
          case .chapters: self.document.analysis.chapters = merged.chapters
          }
          self.document.analysis.states[section.rawValue] = merged.states[section.rawValue]
        }
        self.document.analysis.model = model
        self.document.analysis.revision = snapshot.revision
        if self.document.revision != snapshot.revision { self.document.invalidate() }
        self.lastGenerated = snapshot.revision
        let failures = sections.filter {
          self.document.analysis.states[$0.rawValue]?.phase == .failed
        }
        self.status = failures.isEmpty ? "整理已保存 · 点击节点核对原文" : "部分成果未完成，请查看对应错误并重试"
        self.save()
      } catch {
        for section in sections where !self.document.protected.contains(section.rawValue) {
          self.document.analysis.states[section.rawValue] = VTArtifactState(
            phase: .failed,
            message: (error as? VTError)?.localizedDescription ?? "网络请求未完成；已有内容保留，请检查连接后重试",
            updated: Date(), revision: snapshot.revision)
        }
        self.status = "整理未完成；录音不受影响"
        self.save()
      }
      self.busy = false
    }
  }
  func cancel() {
    generation?.cancel()
    status = "正在取消整理…"
  }
  func validateWithCloud() {
    guard !locked, saved else { return }
    resetTransient()
    document = VTFixture.source()
    document.title = "云端链路验收 · 虚构资料"
    page = "观点图"
    selectedNode = nil
    sourceIDs = []
    if save() { generate() }
  }
  func loadFixture(_ response: URL) {
    guard !locked else { return }
    resetTransient()
    document = VTFixture.source()
    selectedNode = nil
    filterSpeaker = nil
    onlyDisputes = false
    sourceIDs = []
    page = "观点图"
    save()
    analyze(sections: Set(VTSection.allCases), model: "虚构响应 · 模拟验收", scope: "fictional") { doc in
      let raw = try String(contentsOf: response, encoding: .utf8)
      return try await VTModelClient.request(
        document: doc,
        config: VTModelConfig(
          baseURL: "https://example.invalid", model: "fictional", jsonMode: true),
        key: "fictional-only", transport: { _ in (try VTFixture.envelope(raw), 200) })
    }
  }
  func saveSettings(speech: SpeechProfile, text: TextProfile, speechKey: String, textKey: String)
    throws
  {
    guard !locked else { throw VTError.message("请先结束录音和整理再切换服务") }
    let s = try speech.validated()
    let t = try text.validated()
    if !speechKey.isEmpty { try Vault.save(s.keyAccount, speechKey) }
    if !textKey.isEmpty { try Vault.save(t.keyAccount, textKey) }
    settings.upsert(s)
    settings.upsert(t)
    let defaults = UserDefaults.standard
    defaults.set(try JSONEncoder().encode(settings), forKey: "profiles")
    defaults.set(jsonMode, forKey: "jsonMode")
    defaults.set(automatic, forKey: "liveAnalysis")
    defaults.set(finalAutomatic, forKey: "finalAnalysis")
    status = "服务配置已保存，密钥保存在钥匙串"
  }
  func importLegacy(_ folder: URL) {
    guard !locked, let repository = repository else { return }
    var imported = 0
    do {
      let dirs = try FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil)
      for dir in dirs where dir.lastPathComponent != "RecentlyDeleted" {
        let file = dir.appendingPathComponent("meeting.json")
        guard FileManager.default.fileExists(atPath: file.path) else { continue }
        let old = try JSONDecoder().decode(Meeting.self, from: Data(contentsOf: file))
        let importID = vtID(folder.path + old.id)
        if documents.contains(where: { $0.importID == importID }) { continue }
        var next = VTDocument()
        next.title = old.title
        next.created = old.created
        next.importID = importID
        next.notes = old.notes
        next.capture = old.captureState ?? "已导入"
        next.legacyText = [
          "纪要": AnalysisNode.plain(old.summary), "观点": AnalysisNode.plain(old.tree),
          "分歧": AnalysisNode.plain(old.disagreements ?? ""), "待办": AnalysisNode.plain(old.todos),
        ]
        var map: [String: String] = [:]
        for row in old.sentences {
          let sid: String?
          if row.speaker.contains("区分") {
            sid = nil
          } else {
            sid = map[row.speaker] ?? UUID().uuidString
            if map[row.speaker] == nil {
              map[row.speaker] = sid!
              next.speakers.append(VTSpeaker(id: sid!, name: row.speaker))
            }
          }
          next.utterances.append(
            VTUtterance(id: row.id, start: row.start, end: row.end, speakerID: sid, text: row.text))
        }
        let audioFolder = try repository.audioFolder(next.id)
        for rec in old.recordings {
          let from = dir.appendingPathComponent(URL(fileURLWithPath: rec.path).lastPathComponent)
          guard FileManager.default.fileExists(atPath: from.path) else {
            throw VTError.message("有会议录音缺失，导入暂停；原始资料没有改变")
          }
          let to = audioFolder.appendingPathComponent(from.lastPathComponent)
          try FileManager.default.copyItem(at: from, to: to)
          next.audio.append(VTAudio(path: to.path, offset: rec.offset, duration: rec.duration))
        }
        // 连同原始 JSON 保留迁移快照。
        try FileManager.default.copyItem(
          at: file, to: audioFolder.appendingPathComponent("legacy-backup.json"))
        try repository.save(next)
        imported += 1
      }
      refresh()
      if let first = documents.first(where: { !$0.trashed }) { open(first) }
      status = "已导入 \(imported) 场会议；旧目录和原始文件完整保留"
    } catch {
      refresh()
      issue =
        "已导入 \(imported) 场，其余未完成。"
        + ((error as? VTError)?.localizedDescription ?? "请检查所选资料目录、文件权限和磁盘空间")
    }
  }
  func supplementalTranscription() async {
    guard !locked, !document.audio.isEmpty, saved else { return }
    let key = Vault.read(settings.activeSpeech.keyAccount)
    guard !key.isEmpty else {
      showSettings = true
      return
    }
    busy = true
    status = "正在会后补转写…"
    do {
      var rows: [VTUtterance] = []
      var identities = VTDocument()
      for (index, audio) in document.audio.enumerated() {
        let result = try await Cloud(
          config: ServiceConfig(speech: settings.activeSpeech, text: settings.activeText)
        ).diarize(
          Recording(path: audio.path, offset: audio.offset, duration: audio.duration), key: key)
        for row in result {
          let sid =
            row.speaker.contains("区分")
            ? nil : identities.registerVoice(track: "file-" + String(index) + "|" + row.speaker)
          rows.append(
            VTUtterance(
              id: UUID().uuidString, start: row.start, end: row.end, speakerID: sid, text: row.text)
          )
        }
      }
      document.utterances = rows
      document.unfinished = nil
      document.speakers = identities.speakers
      document.invalidate()
      save(reason: "会后补转写前版本")
      status = "补转写已保存，跨录音段身份请人工核对"
    } catch { issue = (error as? AppError)?.message ?? "补转写失败，旧逐字稿完整保留" }
    busy = false
  }
  private func persistStartupTrace(_ trace: VTStartupTrace) {
    let directory = root.appendingPathComponent("diagnostics")
    // 只有阶段、耗时和数字错误码；后台写盘，不作为录音启动的前置步骤。
    diagnosticQueue.async {
      guard let data = try? JSONEncoder().encode(trace) else { return }
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try? data.write(
        to: directory.appendingPathComponent("startup-" + trace.id + ".json"), options: .atomic)
    }
  }
  func dismissDraftsNotice() {
    document.draftsNoticeDismissed = true
    save()
  }
  func cancelQuestion() {
    questionToken = UUID()
    questionTask?.cancel()
    questionTask = nil
    asking = false
    if let id = activeQuestionID,
      let index = document.conversation?.firstIndex(where: { $0.id == id && $0.phase == .waiting })
    {
      document.conversation?[index].phase = .cancelled
      save()
    }
    activeQuestionID = nil
  }
  func ask(call: ((VTDocument, String) async throws -> String)? = nil) async {
    let query = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !asking, !query.isEmpty, !document.utterances.isEmpty else { return }
    let turn = VTChatTurn(question: query)
    document.conversation = (document.conversation ?? []) + [turn]
    question = ""
    activeQuestionID = turn.id
    let snapshot = document
    let config = ServiceConfig(speech: settings.activeSpeech, text: settings.activeText)
    let account = settings.activeText.keyAccount
    let loader = credentialReader
    let token = UUID()
    questionToken = token
    asking = true
    guard save() else {
      asking = false
      return
    }
    let task = Task<String, Error> {
      if let call = call { return try await call(snapshot, query) }
      let key = await loader(account)
      try Task.checkCancellation()
      guard !key.isEmpty else { throw VTError.message("请在设置中保存整理服务的API Key") }
      let text = String(try VTAnalyzer.source(snapshot).prefix(30000))
      return try await Cloud(config: config).chat(
        text: text, question: snapshot.followup(query) + "\n仅基于所给片段，来源引用片段ID；内容可能被截取，不得声称穷尽会议。",
        key: key)
    }
    questionTask = task
    defer {
      if questionToken == token {
        asking = false
        questionTask = nil
        activeQuestionID = nil
      }
    }
    do {
      let result = try await task.value
      guard questionToken == token, document.id == snapshot.id,
        let index = document.conversation?.firstIndex(where: { $0.id == turn.id })
      else { return }
      answer = result
      document.conversation?[index].answer = result
      document.conversation?[index].phase = .answered
      save()
    } catch {
      guard questionToken == token, document.id == snapshot.id,
        let index = document.conversation?.firstIndex(where: { $0.id == turn.id })
      else { return }
      document.conversation?[index].phase = error is CancellationError ? .cancelled : .failed
      document.conversation?[index].answer =
        (error as? VTError)?.localizedDescription ?? "请求未完成，请重试；原有对话已保留。"
      save()
    }
  }
}
