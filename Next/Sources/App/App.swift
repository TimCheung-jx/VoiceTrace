import AppKit
import SwiftUI

@main struct VoiceTraceNextApp: App {
  @NSApplicationDelegateAdaptor(VTDelegate.self) var delegate
  @StateObject private var workspace = VTWorkspace()
  var body: some Scene {
    WindowGroup("声迹VoiceTrace") {
      VTWorkbench(w: workspace).onAppear {
        VTDelegate.workspace = workspace
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.contentView != nil })?.delegate = delegate
        if ProcessInfo.processInfo.environment["VTNEXT_QA"] == "1" { VTNextQA.run(workspace) }
      }
    }.defaultSize(width: 1320, height: 840).commands {
      CommandGroup(replacing: .appSettings) {
        Button("声迹设置…") { workspace.showSettings = true }.keyboardShortcut(",")
      }
      CommandGroup(replacing: .newItem) {
        Button("新建会议") { workspace.create() }.keyboardShortcut("n").disabled(workspace.locked)
      }
    }
  }
}
@MainActor final class VTDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  static var workspace: VTWorkspace?
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard let w = Self.workspace else { return true }
    if w.locked {
      w.issue = "请先结束录音或取消并等待整理完成，再关闭窗口"
      return false
    }
    return w.save()
  }
  func applicationShouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
    guard let w = Self.workspace else { return .terminateNow }
    if w.locked {
      w.issue = "请先结束录音或等待整理结束，再退出"
      return .terminateCancel
    }
    guard w.save() else { return .terminateCancel }
    Vault.clearMemory()
    return .terminateNow
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@MainActor enum VTNextQA {
  private static var started = false
  static func run(_ w: VTWorkspace) {
    guard !started else { return }
    started = true
    guard let response = Bundle.main.url(forResource: "response", withExtension: "json") else {
      return
    }
    // 不调用预设节点：走与真实服务相同的入口，然后从SQLite重新加载。
    w.loadFixture(response)
    Task {
      while w.busy { try? await Task.sleep(nanoseconds: 100_000_000) }
      guard let repo = w.repository, let reloaded = try? repo.load(w.document.id) else { return }
      w.open(reloaded)
      w.page = ProcessInfo.processInfo.environment["VTNEXT_PAGE"] ?? "观点图"
      if ProcessInfo.processInfo.environment["VTNEXT_INSPECT"] == "1",
        let node = reloaded.analysis.graph.nodes.first(where: { $0.kind == .position })
      {
        w.select(node)
      }
      if ProcessInfo.processInfo.environment["VTNEXT_LONG_TRANSCRIPT"] == "1" {
        let one = w.document.registerVoice(track: "qa|voice1")
        let two = w.document.registerVoice(track: "qa|voice2")
        for n in 1...150 {
          w.document.utterances.append(
            VTUtterance(
              id: "qa-long-" + String(n), start: Double(n * 5), end: Double(n * 5 + 4),
              speakerID: n % 2 == 0 ? one : two,
              text: "虚构长逐字稿第\(n)段。用于检验滚动和回到最新；\(n==150 ? "最新定位标记已到达":"仅为界面验收，不是真实会议")。"))
        }
        w.page = "原文"
        w.save()
      }
      if ProcessInfo.processInfo.environment["VTNEXT_WAVE"] == "1" {
        w.recording = true
        w.recordState = "录音中"
        w.level = 0.7
        w.recognition.phase = .live
        w.recognition.lastResult = Date().addingTimeInterval(-3)
        w.status = "模拟声波界面验收，未访问麦克风"
      }
      if ProcessInfo.processInfo.environment["VTNEXT_SPEAKER_SHEET"] == "1" {
        for index in w.document.speakers.indices {
          w.document.speakers[index].name = "发言人\(index + 1)"
          w.document.speakers[index].placeholderNumber = index + 1
        }
        w.showSpeakers = true
      }
      if ProcessInfo.processInfo.environment["VTNEXT_ASK"] == "1" {
        w.question = "本次会议有哪些决定？"
        w.document.conversation = [
          VTChatTurn(
            question: "本次会议有哪些决定？", answer: "**先进行电脑端试点**；手机端在验证结果后再确定范围。", phase: .answered),
          VTChatTurn(
            question: "谁负责跟进？", answer: "周衡负责提交同步验证报告，期限为**周五**；林悦负责验收标准草案，期限为**周三**。",
            phase: .answered),
        ]
        w.question = ""

        w.showAsk = true
      }
      if ProcessInfo.processInfo.environment["VTNEXT_DRAFTS"] == "1" {
        w.document.unfinished = (1...25).map {
          VTDraft(id: "qa-draft-" + String($0), text: "虚构临时结果第\($0)段。用于检查默认收起与关闭，不是真实会议内容。")
        }
        w.page = "原文"
        w.document.draftsNoticeDismissed =
          ProcessInfo.processInfo.environment["VTNEXT_HIDE_DRAFTS"] == "1"
        if ProcessInfo.processInfo.environment["VTNEXT_DRAFT_SHEET"] == "1" { w.showDrafts = true }
        w.save()
      }
      if w.page == "会议库" {
        for index in 1...4 {
          var copy = reloaded
          copy.id = UUID().uuidString
          copy.title = "虚构会议记录\(index)"
          try? w.repository?.save(copy)
        }
        w.refresh()
      }
      if let dir = ProcessInfo.processInfo.environment["VTNEXT_EXPORT_DIR"] {
        let folder = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? VTLayout.make(reloaded.analysis.graph).svg(reloaded).write(
          to: folder.appendingPathComponent("graph.svg"), atomically: true, encoding: .utf8)
        try? VTExporter.graphPNG(reloaded).write(to: folder.appendingPathComponent("graph.png"))
        try? VTExporter.pdf(title: reloaded.title, text: reloaded.plain(.minutes)).write(
          to: folder.appendingPathComponent("minutes.pdf"))
        try? VTExporter.word(title: reloaded.title, text: reloaded.plain(.minutes)).write(
          to: folder.appendingPathComponent("minutes.docx"))
        try? reloaded.plain(.tasks).write(
          to: folder.appendingPathComponent("tasks.md"), atomically: true, encoding: .utf8)
      }
      guard let output = ProcessInfo.processInfo.environment["VTNEXT_SCREENSHOT"] else { return }
      try? await Task.sleep(nanoseconds: 700_000_000)
      guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
        let view = window.contentView
      else { return }
      window.setContentSize(
        NSSize(
          width: Double(ProcessInfo.processInfo.environment["VTNEXT_WIDTH"] ?? "1440") ?? 1440,
          height: 880))
      window.makeFirstResponder(nil)
      window.layoutIfNeeded()
      try? await Task.sleep(nanoseconds: 500_000_000)
      let captureView = window.attachedSheet?.contentView ?? view
      if let rep = captureView.bitmapImageRepForCachingDisplay(in: captureView.bounds) {
        captureView.cacheDisplay(in: captureView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(
          to: URL(fileURLWithPath: output))
      }
      if let sheet = window.attachedSheet {
        window.endSheet(sheet)
        w.showSpeakers = false
        w.showAsk = false
        w.showDrafts = false
      }
      w.recording = false
      NSApp.terminate(nil)
    }
  }
}
