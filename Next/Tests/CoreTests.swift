import Foundation
import SQLite3

@main struct CoreTests {
  static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1])
    let fixture = try String(
      contentsOf: root.appendingPathComponent("Next/Fixtures/response.json"), encoding: .utf8)
    let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
      "voicetrace-next-" + UUID().uuidString)
    var doc = VTFixture.source()
    precondition(Set((0..<100).map { _ in doc.revision }).count == 1)
    let sources = try (0..<100).map { _ in try VTAnalyzer.source(doc) }
    precondition(Set(sources).count == 1)
    var config = VTModelConfig(
      baseURL: "https://example.invalid", model: "fictional", jsonMode: true)
    var requests = 0
    let result = try await VTModelClient.request(
      document: doc, config: config, key: "fictional-only",
      transport: { request in
        requests += 1
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        precondition(
          body["response_format"] != nil
            && request.value(forHTTPHeaderField: "Authorization") == "Bearer fictional-only")
        return (try VTFixture.envelope(fixture), 200)
      })
    doc.analysis = try VTAnalyzer.ingest(result, document: doc, model: "fictional")
    precondition(
      VTSection.allCases.allSatisfy { doc.analysis.states[$0.rawValue]?.phase == .ready })
    precondition(
      doc.analysis.graph.nodes.count == 9 && doc.analysis.graph.edges.count == 7
        && doc.analysis.tasks.count == 2)
    precondition(doc.analysis.graph.nodes.first { $0.kind == .open }?.speakerID == nil)
    precondition(
      doc.sources(doc.analysis.graph.nodes.first { $0.kind == .decision }!.sourceIDs).first!.id
        == "u3")
    precondition(doc.analysis.tasks.first { $0.ownerID == "zhou" }?.deadline == "周五")
    precondition(doc.analysis.tasks.first { $0.ownerID == "lin" }?.deadline == "周三")
    precondition(doc.analysis.minutes.contains { $0.category == "决定" && $0.detail.contains("电脑端") })
    precondition(doc.analysis.disputes.first?.category == "明确意见冲突")
    var repo: VTRepository? = try VTRepository(root: temp)
    try repo!.save(doc)
    doc.completed.insert(doc.analysis.tasks[0].id)
    try repo!.save(doc, reason: "完成任务")
    repo = nil
    repo = try VTRepository(root: temp)
    let reopened = try repo!.load(doc.id)!
    let history = try repo!.history(doc.id)
    precondition(reopened == doc && reopened.completed.count == 1 && history.count == 1)
    let layout = VTLayout.make(reopened.analysis.graph)
    precondition(layout.items.count == 9)
    for (i, a) in layout.items.enumerated() {
      for b in layout.items.dropFirst(i + 1) {
        precondition(
          !(a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height
            && a.y + a.height > b.y), "节点不能重叠")
      }
    }
    let svg = layout.svg(reopened)
    precondition(svg.contains("<path") && svg.contains("首轮仅覆盖电脑端") && svg.contains("反对扩大范围"))
    try svg.write(to: temp.appendingPathComponent("graph.svg"), atomically: true, encoding: .utf8)
    // 单个页面失败不会抹掉其他页面或已经有效的图形。
    var obj = try JSONSerialization.jsonObject(with: Data(fixture.utf8)) as! [String: Any]
    obj["tasks"] = "malformed"
    let partial = try VTAnalyzer.ingest(
      String(decoding: JSONSerialization.data(withJSONObject: obj), as: UTF8.self), document: doc,
      previous: doc.analysis, model: "fictional")
    precondition(
      partial.states["tasks"]?.phase == .failed && partial.tasks == doc.analysis.tasks
        && partial.states["graph"]?.phase == .ready)
    var graph = obj["graph"] as! [String: Any]
    var nodes = graph["nodes"] as! [[String: Any]]
    nodes[1]["speakerID"] = "invented"
    graph["nodes"] = nodes
    obj["graph"] = graph
    let bad = try VTAnalyzer.ingest(
      String(decoding: JSONSerialization.data(withJSONObject: obj), as: UTF8.self), document: doc,
      previous: doc.analysis, model: "fictional")
    precondition(bad.states["graph"]?.phase == .failed && bad.graph == doc.analysis.graph)
    do {
      _ = try await VTModelClient.request(
        document: doc, config: config, key: "fictional-only",
        transport: { _ in (try VTFixture.envelope(fixture, finish: "length"), 200) })
      preconditionFailure()
    } catch {}
    do {
      _ = try await VTModelClient.request(
        document: doc, config: config, key: "fictional-only",
        transport: { _ in (Data("sensitive-provider-body".utf8), 401) })
      preconditionFailure()
    } catch { precondition(!error.localizedDescription.contains("sensitive")) }
    config.jsonMode = false
    _ = try await VTModelClient.request(
      document: doc, config: config, key: "fictional-only",
      transport: { request in
        let b = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        precondition(b["response_format"] == nil)
        return (try VTFixture.envelope(fixture), 200)
      })
    var protected = doc
    protected.protected.insert("tasks")
    let merged = VTAnalyzer.merge([partial], document: protected, previous: doc.analysis)
    precondition(merged.tasks == doc.analysis.tasks)
    let topic = doc.analysis.graph.nodes.first { $0.kind == .topic }!.id
    precondition(
      VTLayout.make(doc.analysis.graph, collapsed: [topic]).items.count < layout.items.count)
    var injected = doc
    injected.analysis.graph.nodes[0].title = "<script>alert('x')</script>"
    let safe = VTLayout.make(injected.analysis.graph).svg(injected)
    precondition(!safe.contains("<script>") && safe.contains("&lt;script&gt;"))
    var seq = doc
    seq.timing = "sequence"
    precondition(seq.timeLabel(seq.utterances[0]) == "第1段")
    let future = temp.appendingPathComponent("future")
    try FileManager.default.createDirectory(at: future, withIntermediateDirectories: true)
    var db: OpaquePointer?
    precondition(
      sqlite3_open(future.appendingPathComponent("workspace.sqlite").path, &db) == SQLITE_OK)
    sqlite3_exec(db, "PRAGMA user_version=99", nil, nil, nil)
    sqlite3_close(db)
    do {
      _ = try VTRepository(root: future)
      preconditionFailure("不能降级改写未来版本资料库")
    } catch {}
    let clock = Date(timeIntervalSince1970: 1000)
    var health = VTRecognitionHealth()
    health.phase = .live
    health.connectedAt = clock
    health.lastVoice = clock.addingTimeInterval(31)
    precondition(health.stalled(at: clock.addingTimeInterval(32)))
    precondition(!health.stalled(at: clock.addingTimeInterval(40)))
    health.lastResult = clock.addingTimeInterval(31)
    precondition(!health.stalled(at: clock.addingTimeInterval(32)))
    let relay = VTPCMRelay()
    var firstSink: AsyncStream<Data>.Continuation!
    let first = AsyncStream<Data> { firstSink = $0 }
    relay.install(firstSink, token: "old")
    _ = relay.push(Data([1]))
    var secondSink: AsyncStream<Data>.Continuation!
    let second = AsyncStream<Data> { secondSink = $0 }
    relay.install(secondSink, token: "new")
    _ = relay.push(Data([2]))
    relay.finish()
    var one = first.makeAsyncIterator()
    var two = second.makeAsyncIterator()
    let firstBytes = await one.next()
    let oldEnd = await one.next()
    let secondBytes = await two.next()
    precondition(firstBytes == Data([1]) && oldEnd == nil && secondBytes == Data([2]))
    print("PASS: 识别停滞判断区分静音与有声无结果；音频重连切换发送队列，无旧连接残留。")
    let pageTexts = ["总览", "原文", "观点图", "会议纪要", "行动"].map { doc.pageText($0) }
    precondition(pageTexts.allSatisfy { !$0.isEmpty } && Set(pageTexts).count == 5)
    precondition(doc.pageText("原文").contains(doc.utterances[0].text))
    precondition(doc.pageText("会议纪要") == doc.plain(.minutes) && doc.pageText("行动").contains("负责人"))
    print("PASS: 五个页面分别输出自己的内容，原文保留说话人和时间，待办保留负责人与期限。")
    var trace = VTStartupTrace()
    trace.record("不应记录的任意文本")
    precondition(trace.events.isEmpty)
    for _ in 0..<100 { trace.record("requested") }
    precondition(trace.events.count == 32)
    trace.record("capture_failed", code: 7)
    trace.record("audio_paused")
    precondition(
      trace.events.count == 32 && trace.hasFailure && trace.events[30].code == 7
        && trace.events.last?.stage == "audio_paused")
    let traceJSON =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(trace)) as! [String: Any]
    precondition(Set(traceJSON.keys) == ["id", "events"])
    let entry = (traceJSON["events"] as! [[String: Any]])[0]
    precondition(Set(entry.keys) == ["stage", "milliseconds", "code"])
    var privateDraft = doc
    privateDraft.unfinished = [VTDraft(id: "hidden", text: "SYNTHETIC_DRAFT_NOT_IN_SUMMARY")]
    privateDraft.conversation = [VTChatTurn(question: "SYNTHETIC_CHAT_NOT_IN_SUMMARY")]
    let summaryInput = try VTAnalyzer.source(privateDraft)
    precondition(
      !summaryInput.contains("SYNTHETIC_DRAFT") && !summaryInput.contains("SYNTHETIC_CHAT"))
    print("PASS: 启动诊断字段白名单、32阶段上限；未定稿与问答历史不进入会议整理原文。")
    var voices = VTDocument()
    let a = voices.registerVoice(track: "segment1|voice0")
    let b = voices.registerVoice(track: "segment1|voice1")
    precondition(a != b && voices.speaker(a) == "发言人1" && voices.speaker(b) == "发言人2")
    precondition(voices.registerVoice(track: "segment1|voice0") == a && voices.speakers.count == 2)
    let another = voices.registerVoice(track: "segment2|voice0")
    precondition(another != a && voices.speaker(another) == "发言人3")
    try voices.nameSpeaker(a, name: "张经理")
    precondition(
      voices.speaker(a) == "张经理" && voices.speakers.first { $0.id == a }?.placeholderNumber == 1)
    let oldPerson = try JSONDecoder().decode(
      VTSpeaker.self, from: Data("{\"id\":\"legacy\",\"name\":\"本段发言人1 · 第1段\"}".utf8))
    var legacyPersonDoc = VTDocument()
    legacyPersonDoc.speakers = [oldPerson]
    precondition(legacyPersonDoc.speaker("legacy") == "发言人1")
    var follow = VTTranscriptFollow()
    follow.receivedFinal()
    precondition(follow.following && follow.unread == 0)
    follow.userScrolled()
    follow.receivedFinal()
    follow.receivedFinal()
    precondition(!follow.following && follow.unread == 2)
    follow.returnToLatest()
    precondition(follow.following && follow.unread == 0)
    print("PASS: 匿名声音编号、分段隔离、统一命名、旧发言人资料兼容；最新文稿跟随/暂停/未读/返回状态。")
    print(
      "PASS: API响应→结构校验→SQLite事务→新实例重开→9节点7连线→原文定位→SVG；任务完成及修订保存；部分失败保留；虚构身份拒绝；响应截断、鉴权与兼容模式。未联网、未读取密钥。"
    )
    print("验收图形：" + temp.appendingPathComponent("graph.svg").path)
  }
}
