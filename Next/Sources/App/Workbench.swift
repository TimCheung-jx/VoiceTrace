import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum VTStyle {
  static let accent = Color(red: 0.31, green: 0.27, blue: 0.9)
  static let canvas = Color(
    nsColor: NSColor(
      name: nil,
      dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
          ? NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 1)
          : NSColor(calibratedRed: 0.967, green: 0.972, blue: 0.98, alpha: 1)
      }))
  static let soft = Color(nsColor: .controlBackgroundColor)
  static let line = Color.primary.opacity(0.12)
}
struct VTEmpty: View {
  let title: String
  let detail: String
  let symbol: String
  var body: some View {
    VStack(spacing: 15) {
      Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(
        VTStyle.accent)
      Text(title).font(.title3.weight(.semibold))
      Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(
        maxWidth: 380)
    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
  }
}
struct VTWorkbench: View {
  @ObservedObject var w: VTWorkspace
  @State private var selection = Set<String>()
  @State private var transcriptFollow = VTTranscriptFollow()
  @State private var rename = false
  @State private var name = ""
  @State private var renameID: String?
  @State private var importPanel = false
  @State private var backupSheet = false
  @State private var editor: VTUtterance?
  @State private var editNode: VTNode?
  var currentSection: VTSection {
    switch w.page {
    case "观点图": return w.onlyDisputes ? .disputes : .graph
    case "行动": return .tasks
    default: return .minutes
    }
  }
  var body: some View {
    HSplitView {
      sidebar.frame(minWidth: 205, idealWidth: 220, maxWidth: 270)
      VStack(spacing: 0) {
        header
        if w.recording {
          VTRecognitionBar(w: w)
        } else if w.startupTrace.hasFailure {
          HStack {
            Label("最近一次录音启动或恢复失败", systemImage: "exclamationmark.circle")
            Spacer()
            Button("查看启动诊断") { w.showStartupInfo = true }
          }
          .font(.caption).foregroundStyle(.orange).padding(.horizontal, 24).padding(.bottom, 10)
        }
        Divider()
        if !w.saved {
          Label("保存失败：请导出备份，暂勿退出", systemImage: "exclamationmark.triangle.fill").foregroundStyle(
            .red
          ).padding(10)
        }
        if w.document.trashed && w.page != "会议库" {
          VTEmpty(title: "会议位于最近删除", detail: "请先恢复会议，再继续查看或修改。", symbol: "trash")
        } else {
          navigation
          Divider()
          content
        }
        Divider()
        HStack {
          Circle().fill(w.saved ? Color.green : Color.red).frame(width: 5, height: 5)
          Text(w.saved ? "已保存在本机" : "保存失败")
          Spacer()
          Text(w.status).lineLimit(1)
        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 18).frame(
          height: 29)
      }.frame(minWidth: 660)
    }.background(Color(nsColor: .windowBackgroundColor)).tint(VTStyle.accent).frame(
      minWidth: 960, minHeight: 680
    )
    .onChange(of: w.document.id) { _ in transcriptFollow.returnToLatest() }
    .onChange(of: w.search) { _ in selection = [] }
    .onChange(of: w.showTrash) { _ in selection = [] }
    .sheet(isPresented: $w.showSettings) { VTSettings(w: w) }
    .sheet(isPresented: $w.showSpeakers) { VTSpeakerEditor(w: w) }
    .sheet(isPresented: $w.showAsk) { VTAskView(w: w) }
    .sheet(isPresented: $w.showDrafts) { VTDraftsView(w: w) }
    .sheet(isPresented: $w.showStartupInfo) { VTStartupInfoView(w: w) }
    .sheet(item: $editor) { row in VTTranscriptEditor(w: w, row: row) }
    .sheet(item: $editNode) { node in VTNodeEditor(w: w, node: node) }
    .sheet(isPresented: $backupSheet) { VTHistoryView(w: w) }
    .alert(
      "声迹", isPresented: Binding(get: { !w.issue.isEmpty }, set: { if !$0 { w.issue = "" } })
    ) {
      Button("确定") { w.issue = "" }
    } message: {
      Text(w.issue)
    }
    .alert("重命名会议", isPresented: $rename) {
      TextField("会议名称", text: $name)
      Button("取消", role: .cancel) {}
      Button("保存") {
        w.renameMeeting(renameID ?? w.document.id, title: name)
      }
    }
  }
  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 9) {
        Image(systemName: "waveform.circle.fill").font(.system(size: 27)).foregroundStyle(
          VTStyle.accent)
        VStack(alignment: .leading, spacing: 2) {
          Text("声迹").font(.system(size: 18, weight: .semibold))
          Text("VoiceTrace").font(.system(size: 10)).foregroundStyle(.secondary)
        }
      }.padding(.top, 24)
      Button {
        w.create()
      } label: {
        Label("新建会议", systemImage: "plus").frame(maxWidth: .infinity)
      }.buttonStyle(.borderedProminent).controlSize(.large).disabled(w.locked || !w.saved)
      TextField("搜索会议", text: $w.search).textFieldStyle(.roundedBorder)
      HStack {
        Button("会议库") {
          w.showTrash = false
          w.page = "会议库"
        }.foregroundStyle(
          w.showTrash ? Color.secondary : VTStyle.accent)
        Spacer()
        Button {
          w.showTrash.toggle()
          w.page = "会议库"
        } label: {
          Image(systemName: "trash")
        }.help("最近删除")
      }.buttonStyle(.plain)
      ScrollView {
        LazyVStack(spacing: 4) {
          ForEach(w.visible) { doc in
            Button {
              w.open(doc)
            } label: {
              VStack(alignment: .leading, spacing: 7) {
                Text(doc.title).font(
                  .system(size: 13, weight: w.document.id == doc.id ? .semibold : .regular)
                ).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                  Text(doc.created, style: .date)
                  Spacer()
                  Text("\(doc.utterances.count) 段")
                }.font(.system(size: 10)).foregroundStyle(.secondary)
              }.padding(12).background(
                w.document.id == doc.id ? VTStyle.accent.opacity(0.09) : Color.clear
              ).clipShape(RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).disabled(w.locked || !w.saved).contextMenu {
              if doc.trashed {
                Button("恢复会议") { w.moveToTrash([doc.id], restore: true) }
              } else {
                Button("重命名") {
                  renameID = doc.id
                  name = doc.title
                  rename = true
                }
                Button("移入最近删除", role: .destructive) { w.moveToTrash([doc.id]) }
              }
            }
          }
        }
      }
      Spacer(minLength: 0)
      Menu {
        Button("导入旧版会议资料…") { chooseImport() }
        Button("导入逐字稿…") { importTranscript() }
        Button("恢复文字备份…") { restoreTextBackup() }
        Button("查看虚构流程验收") {
          if let url = Bundle.main.url(forResource: "response", withExtension: "json") {
            w.loadFixture(url)
          }
        }
        Button("录音启动诊断") { w.showStartupInfo = true }
        Button("恢复中断录音") { w.recoverRecordings() }
        Button("修订历史") {
          w.history = (try? w.repository?.history(w.document.id)) ?? []
          backupSheet = true
        }
        Button("打开本地资料目录") { NSWorkspace.shared.open(w.root) }
      } label: {
        Label("资料与历史", systemImage: "folder")
      }.menuStyle(.borderlessButton).disabled(w.locked)
      Button {
        w.showSettings = true
      } label: {
        Label("设置与服务", systemImage: "slider.horizontal.3")
      }.buttonStyle(.plain)
      Text("0.13.1 · 待真实试录验收").font(.system(size: 10)).foregroundStyle(.secondary)
    }.padding(.horizontal, 16).padding(.bottom, 20).background(.ultraThinMaterial)
  }
  private var header: some View {
    HStack(alignment: .center, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text(w.document.title).font(.system(size: 21, weight: .semibold)).lineLimit(1)
          .textSelection(.enabled)
        HStack(spacing: 12) {
          Text(w.document.created, style: .date)
          Text(w.recordState)

        }.font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Spacer(minLength: 10)
      if w.recording {
        VTRecordingWaveform(level: w.level).fixedSize(horizontal: true, vertical: false)
        Button("暂停") { w.stop(pause: true) }.buttonStyle(.bordered)
        Button {
          w.stop()
        } label: {
          Label("结束录音", systemImage: "stop.fill")
        }.buttonStyle(.borderedProminent).tint(.red)
      } else if w.preparing || w.recordState == "正在启动麦克风" {
        ProgressView().controlSize(.small)
        Text("正在启动麦克风…").font(.callout)
      } else {
        Button {
          Task { await w.start() }
        } label: {
          Label(
            w.recordState == "已暂停" ? "继续录音" : w.document.audio.isEmpty ? "开始录音" : "追加录音",
            systemImage: "mic.fill")
        }.buttonStyle(.borderedProminent).disabled(w.locked || w.document.trashed || !w.saved)
      }
      Button {
        w.showAsk = true
      } label: {
        Label("AI 问答", systemImage: "bubble.left.and.text.bubble.right")
      }.buttonStyle(.bordered).disabled(w.document.utterances.isEmpty).help("向本次会议提问")
    }.controlSize(.large).padding(.horizontal, 24).padding(.vertical, 20)
  }
  private var navigation: some View {
    HStack(spacing: 4) {
      ForEach(["总览", "原文", "观点图", "会议纪要", "行动", "笔记"], id: \.self) { page in
        Button {
          w.page = page
        } label: {
          Text(page == "行动" ? "待办清单" : page).font(
            .system(size: 13, weight: w.page == page ? .semibold : .regular)
          ).padding(
            .horizontal, 15
          ).padding(.vertical, 10).foregroundStyle(
            w.page == page ? VTStyle.accent : Color.secondary
          ).background(w.page == page ? VTStyle.accent.opacity(0.07) : Color.clear).clipShape(
            RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
      }
      Spacer()
      if w.busy {
        ProgressView().controlSize(.small)
        Button("取消") { w.cancel() }.buttonStyle(.borderless)
      } else {
        Button {
          w.generate()
        } label: {
          Label("整理会议", systemImage: "sparkles")
        }.buttonStyle(.borderless).disabled(w.document.utterances.isEmpty || !w.saved)
      }

    }.padding(.horizontal, 18).padding(.bottom, 10)
  }
  private var artifactToolbar: some View {
    HStack(spacing: 14) {
      Button {
        copyCurrent()
      } label: {
        Label("复制", systemImage: "doc.on.doc")
      }.disabled(exportText.isEmpty)
      Menu {
        Button("下载 Word 文件…") {
          VTExporter.exportWord(title: w.document.title + "-" + exportPageName, text: exportText)
        }
        Button("下载 PDF 文件…") {
          VTExporter.exportPDF(title: w.document.title + "-" + exportPageName, text: exportText)
        }
        Button("下载 Markdown…") { exportTextFile() }
        Button("下载纯文本…") { exportTextFile(ext: "txt") }
        if w.page == "观点图" {
          Divider()
          Button("下载观点图 SVG…") { exportGraph() }
          Button("下载观点图 PNG…") { VTExporter.exportGraph(w.document) }
        }
        Divider()
        Button("下载会议文字备份…") { VTExporter.exportBackup(w.document) }
      } label: {
        Label("下载", systemImage: "arrow.down.to.line")
      }.menuStyle(.borderlessButton).fixedSize().disabled(exportText.isEmpty)
      VTFileShareButton(enabled: !exportText.isEmpty) {
        try VTExporter.shareFile(
          w.document, title: w.page == "行动" ? "待办清单" : w.page, text: exportText,
          graph: w.page == "观点图")
      }.frame(width: 74, height: 27)
      Spacer()
      if w.page == "会议纪要" || w.page == "观点图" || w.page == "行动" {
        Menu("更多") {
          Button(w.document.protected.contains(currentSection.rawValue) ? "解除当前成果保护" : "保护当前成果") {
            if w.document.protected.contains(currentSection.rawValue) {
              w.document.protected.remove(currentSection.rawValue)
            } else {
              w.document.protected.insert(currentSection.rawValue)
            }
            w.save(reason: "更改人工保护")
          }
        }.menuStyle(.borderlessButton).fixedSize()
      }
    }.controlSize(.regular).padding(.horizontal, 24).padding(.vertical, 10)
  }
  private func copyCurrent() {
    do {
      let item = NSPasteboardItem()
      item.setString(exportText, forType: .string)
      if w.page == "观点图" { item.setData(try VTExporter.graphPNG(w.document), forType: .png) }
      NSPasteboard.general.clearContents()
      NSPasteboard.general.writeObjects([item])
      w.status = "已复制" + (w.page == "行动" ? "待办清单" : w.page)
    } catch { w.issue = error.localizedDescription }
  }
  @ViewBuilder private var content: some View {
    VStack(spacing: 0) {
      if w.page != "会议库" {
        artifactToolbar
        Divider()
      }
      if w.page == "会议纪要" || w.page == "观点图" || w.page == "行动" { stateBar(currentSection) }
      if w.page == "会议库" {
        library
      } else if w.page == "观点图" {
        HSplitView {
          VTGraphView(w: w).frame(minWidth: 520)
          if !w.sourceIDs.isEmpty { inspector.frame(minWidth: 240, idealWidth: 290, maxWidth: 360) }
        }
      } else if w.page == "原文" {
        transcript
      } else if w.page == "行动" {
        tasks
      } else if w.page == "笔记" {
        VStack(alignment: .leading, spacing: 12) {
          Text("会议笔记").font(.title2.weight(.semibold))
          Text("手动记录，自动保存。AI 整理不会改写此处。").font(.callout).foregroundStyle(.secondary)
          TextEditor(
            text: Binding(
              get: { w.document.notes },
              set: {
                w.document.notes = $0
                w.save()
              })
          ).font(.system(size: 15)).scrollContentBackground(.hidden)
        }.padding(24)
      } else if w.page == "会议纪要" {
        minutes
      } else {
        overview
      }
    }
  }
  private func stateBar(_ section: VTSection) -> some View {
    let state = w.document.analysis.states[section.rawValue] ?? VTArtifactState()
    return HStack(spacing: 9) {
      Image(systemName: state.phase == .failed ? "exclamationmark.circle" : "circle.dotted")
        .foregroundStyle(state.phase == .failed ? Color.orange : Color.secondary)
      Text(state.phase.label).fontWeight(.medium)
      if w.document.protected.contains(section.rawValue) {
        Label("人工保护", systemImage: "lock")
      } else if !state.message.isEmpty {
        Text(state.message).lineLimit(3)
      }
      Spacer()
      if state.phase == .failed || state.phase == .stale {
        Button("重试此项") {
          w.generate(sections: section == .disputes ? [.graph, .disputes] : [section])
        }.disabled(w.busy)
      }
    }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(
      .vertical, 10
    ).background(state.phase == .failed ? Color.orange.opacity(0.07) : VTStyle.soft)
  }
  private var library: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(w.showTrash ? "最近删除" : "全部会议").font(.title2.weight(.semibold))
        Spacer()
        Toggle(
          "全选",
          isOn: Binding(
            get: { !w.visible.isEmpty && Set(w.visible.map(\.id)).isSubset(of: selection) },
            set: { selection = $0 ? Set(w.visible.map(\.id)) : [] })
        ).toggleStyle(.checkbox).disabled(w.locked)
        Text("已选 \(selection.count) 项").font(.caption).foregroundStyle(.secondary)
        Button(w.showTrash ? "恢复所选" : "移入最近删除") {
          w.moveToTrash(selection, restore: w.showTrash)
          selection = []
        }.disabled(selection.isEmpty || w.locked)
      }
      Table(w.visible) {
        TableColumn("选择") { doc in
          Toggle(
            "选择" + doc.title,
            isOn: Binding(
              get: { selection.contains(doc.id) },
              set: { if $0 { selection.insert(doc.id) } else { selection.remove(doc.id) } })
          ).toggleStyle(.checkbox).labelsHidden().disabled(w.locked)
        }.width(36)
        TableColumn("会议名称") { doc in
          HStack {
            Button(doc.title) { w.open(doc) }.buttonStyle(.plain).disabled(w.locked)
            Spacer()
            Button {
              renameID = doc.id
              name = doc.title
              rename = true
            } label: {
              Image(systemName: "pencil")
            }.buttonStyle(.borderless).help("重命名会议").disabled(w.locked || doc.trashed)
          }.contextMenu {
            Button("打开会议") { w.open(doc) }.disabled(w.locked)
            Button("重命名") {
              renameID = doc.id
              name = doc.title
              rename = true
            }.disabled(w.locked || doc.trashed)
            Button(doc.trashed ? "恢复会议" : "移入最近删除") {
              w.moveToTrash([doc.id], restore: doc.trashed)
            }.disabled(w.locked)
          }
        }
        TableColumn("日期") { doc in
          Text(doc.created.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute()))
        }.width(125)
        TableColumn("原文") { doc in Text("\(doc.utterances.count) 段") }.width(65)
        TableColumn("录音") { doc in Text(vtTime(doc.audio.reduce(0, { $0 + $1.duration }))) }.width(
          75)
      }
      Text("勾选会议后批量删除；点击铅笔重命名，点击名称打开会议。最近删除中的资料可以恢复。").font(.caption).foregroundStyle(.secondary)
    }.padding(24)
  }
  private var overview: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        Text("会议总览").font(.title2.weight(.semibold))
        Text(
          "录音 " + vtTime(w.document.audio.reduce(0) { $0 + $1.duration })
            + "    原文 \(w.document.utterances.count) 段    已区分声音 \(w.document.speakers.count) 位"
        ).font(.callout).foregroundStyle(.secondary)
        if w.document.utterances.isEmpty {
          VTEmpty(title: "尚无会议内容", detail: "点击开始录音，或导入逐字稿后生成会议成果。", symbol: "waveform")
          Button("导入逐字稿…") { importTranscript() }
        } else {
          if w.document.analysis.minutes.isEmpty {
            Text("点击右上角“整理会议”，生成纪要、观点图与待办清单。").foregroundStyle(.secondary)
          }
          ForEach(Array(w.document.analysis.minutes.prefix(3))) { row in
            VStack(alignment: .leading, spacing: 8) {
              Text(row.category + " · " + row.title).font(.headline)
              Text(row.detail).lineSpacing(5).textSelection(.enabled)
              sourceButtons(row.sourceIDs)
            }
          }
          Button("查看完整会议纪要") { w.page = "会议纪要" }
          Divider()
          Text("会议成果").font(.headline)
          ForEach(VTSection.allCases, id: \.rawValue) { section in
            HStack {
              Text(section.label).frame(width: 90, alignment: .leading)
              Text((w.document.analysis.states[section.rawValue] ?? VTArtifactState()).phase.label)
                .foregroundStyle(.secondary)
              Spacer()
              Button("查看") {
                switch section {
                case .minutes, .chapters: w.page = "会议纪要"
                case .graph:
                  w.onlyDisputes = false
                  w.page = "观点图"
                case .disputes:
                  w.onlyDisputes = true
                  w.page = "观点图"
                case .tasks: w.page = "行动"
                }
              }
            }.font(.callout)
          }
        }
      }.padding(28).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity)
    }
  }
  private var minutes: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        HStack {
          Text("AI 会议纪要").font(.title2.weight(.semibold))
          Spacer()
          Button("导出 Word") {
            VTExporter.exportWord(title: w.document.title, text: w.document.plain(.minutes))
          }.disabled(w.document.analysis.minutes.isEmpty)
          Button("导出 PDF") {
            VTExporter.exportPDF(title: w.document.title, text: w.document.plain(.minutes))
          }.disabled(w.document.analysis.minutes.isEmpty)
        }
        if w.document.utterances.isEmpty {
          VTEmpty(title: "从一场会议开始", detail: "录音或导入原文，也可以先用虚构资料检查新工作台。", symbol: "waveform")
          HStack(spacing: 15) {
            Button("运行虚构流程验收") {
              if let url = Bundle.main.url(forResource: "response", withExtension: "json") {
                w.loadFixture(url)
              }
            }.buttonStyle(.borderedProminent)
            Button("导入旧版会议资料…") { chooseImport() }
          }.frame(maxWidth: .infinity)
          Text("虚构验收只验证工程链路，不调用真实API。").font(.caption).foregroundStyle(.secondary).frame(
            maxWidth: .infinity)
        } else if w.document.analysis.minutes.isEmpty {
          VTEmpty(
            title: "会议尚未整理", detail: "点击右上角“整理会议”，生成纪要、思维导图、分歧和行动事项。生成后可导出 Word、PDF 或图形文件。",
            symbol: "doc.text.magnifyingglass")
        } else {
          ForEach(["决定", "待确认", "讨论", "背景"], id: \.self) { category in
            let rows = w.document.analysis.minutes.filter { $0.category == category }
            if !rows.isEmpty {
              VStack(alignment: .leading, spacing: 15) {
                Text(category).font(.system(size: 19, weight: .semibold))
                ForEach(rows) { row in
                  VStack(alignment: .leading, spacing: 9) {
                    Text(row.title).font(.system(size: 15, weight: .semibold))
                    Text(row.detail).font(.system(size: 14)).lineSpacing(6).textSelection(.enabled)
                    sourceButtons(row.sourceIDs)
                  }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
              }
            }
          }
        }
        if !w.document.analysis.chapters.isEmpty {
          VStack(alignment: .leading, spacing: 15) {
            Text("会议章节").font(.title3.weight(.semibold))
            ForEach(w.document.analysis.chapters) { chapter in
              HStack(alignment: .top, spacing: 15) {
                Button(
                  w.document.sources(chapter.sourceIDs).first.map { w.document.timeLabel($0) }
                    ?? "—"
                ) {
                  w.reveal(chapter.sourceIDs)
                  w.page = "原文"
                }.font(.system(size: 12, design: .monospaced))
                VStack(alignment: .leading, spacing: 7) {
                  Text(chapter.title).font(.callout.bold())
                  Text(chapter.detail).font(.callout).foregroundStyle(.secondary)
                }
              }
            }
          }
        }
        if let legacy = w.document.legacyText {
          DisclosureGroup("查看导入时保留的旧版文字") {
            ForEach(legacy.keys.sorted(), id: \.self) { key in
              Text(key).font(.headline)
              Text(legacy[key] ?? "").font(.callout).textSelection(.enabled)
            }
          }
        }
      }.padding(28).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity)
    }
  }
  private var transcript: some View {
    ScrollViewReader { proxy in
      VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("逐字稿").font(.title2.weight(.semibold))
            Spacer()
            if !(w.document.unfinished ?? []).isEmpty {
              Button("未定稿（\((w.document.unfinished?.count ?? 0))）") { w.showDrafts = true }
            }
            Button("确认发言人身份") { w.showSpeakers = true }.disabled(w.locked)
            Button("会后区分发言人") { importPanel = true }.disabled(w.locked || w.document.audio.isEmpty)
          }
          HStack(spacing: 15) {
            Toggle(
              "跟随最新",
              isOn: Binding(
                get: { transcriptFollow.following },
                set: { enabled in
                  if enabled { jumpToLatest(proxy) } else { transcriptFollow.userScrolled() }
                })
            ).toggleStyle(.checkbox)
            Button {
              jumpToLatest(proxy)
            } label: {
              Label(
                transcriptFollow.unread > 0 ? "回到最新（\(transcriptFollow.unread)段新稿）" : "回到最新",
                systemImage: "arrow.down.to.line")
            }.buttonStyle(.bordered)
            if !transcriptFollow.following { Text("阅读历史中，新增文字不会打断").foregroundStyle(.secondary) }
            Spacer()
          }.font(.system(size: 12))
          if !(w.document.unfinished ?? []).isEmpty, w.document.draftsNoticeDismissed != true {
            HStack {
              Label("已保留\((w.document.unfinished?.count ?? 0))段未定稿，默认收起", systemImage: "tray")
              Button("查看") { w.showDrafts = true }
              Spacer()
              Button {
                w.dismissDraftsNotice()
              } label: {
                Image(systemName: "xmark")
              }.buttonStyle(.borderless).help("关闭提示，文字仍保留")
            }.font(.caption).foregroundStyle(.secondary)
          }
        }.padding(.horizontal, 24).padding(.vertical, 15)
        Divider()
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(w.document.utterances) { row in
              HStack(alignment: .top, spacing: 15) {
                Text(w.document.speaker(row.speakerID).prefix(1)).font(.callout.bold())
                  .foregroundStyle(VTStyle.accent).frame(width: 30, height: 30).background(
                    VTStyle.accent.opacity(0.08)
                  ).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 10) {
                  HStack {
                    Text(w.document.speaker(row.speakerID)).fontWeight(.medium)
                    Button(w.document.timeLabel(row)) { w.play(row) }.monospacedDigit()
                    Spacer()
                    Button("纠错") { editor = row }.disabled(w.locked)
                  }.font(.system(size: 11)).foregroundStyle(.secondary)
                  Text(row.text).font(.system(size: 15)).lineSpacing(7).textSelection(.enabled)
                    .frame(
                      maxWidth: .infinity, alignment: .leading)
                }.padding(.bottom, 22)
              }.padding(14).background(
                w.sourceIDs.contains(row.id) ? VTStyle.accent.opacity(0.06) : Color.clear
              ).clipShape(RoundedRectangle(cornerRadius: 8)).id(row.id)
            }

            if !w.partial.isEmpty { Text(w.partial + " ▍").foregroundStyle(.secondary).padding(15) }
            Color.clear.frame(height: 2).id("vt-transcript-latest")
          }.padding(24)
        }.background(VTTranscriptScrollObserver { transcriptFollow.userScrolled() })
          .onChange(of: w.document.utterances.count) { _ in
            transcriptFollow.receivedFinal()
            if transcriptFollow.following {
              DispatchQueue.main.async { proxy.scrollTo("vt-transcript-latest", anchor: .bottom) }
            }
          }
          .onChange(of: w.partial) { _ in
            if transcriptFollow.following {
              DispatchQueue.main.async { proxy.scrollTo("vt-transcript-latest", anchor: .bottom) }
            }
          }
          .onChange(of: w.sourceIDs) { ids in
            if let first = ids.first {
              transcriptFollow.userScrolled()
              proxy.scrollTo(first, anchor: .center)
            }
          }
          .onAppear {
            if let first = w.sourceIDs.first {
              transcriptFollow.userScrolled()
              DispatchQueue.main.async { proxy.scrollTo(first, anchor: .center) }
            } else if w.recording || ProcessInfo.processInfo.environment["VTNEXT_LATEST"] == "1" {
              DispatchQueue.main.async { proxy.scrollTo("vt-transcript-latest", anchor: .bottom) }
            }
          }
      }
    }.confirmationDialog("会后补转写会备份当前逐字稿并生成新版本，音频将发送到所选语音服务。", isPresented: $importPanel) {
      Button("备份并补转写") { Task { await w.supplementalTranscription() } }
    }
  }
  private func jumpToLatest(_ proxy: ScrollViewProxy) {
    transcriptFollow.returnToLatest()
    w.sourceIDs = []
    DispatchQueue.main.async { proxy.scrollTo("vt-transcript-latest", anchor: .bottom) }
  }
  private var tasks: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Text("待办清单").font(.title2.weight(.semibold))
          Spacer()
          Text(
            "\(w.document.analysis.tasks.filter{w.document.completed.contains($0.id)}.count) 已完成"
          ).font(.caption).foregroundStyle(.secondary)
        }.padding(.bottom, 8)
        if w.document.analysis.tasks.isEmpty {
          VTEmpty(
            title: w.document.analysis.states["tasks"]?.phase == .ready ? "原文没有明确行动事项" : "尚未生成行动事项",
            detail: "任务负责人和期限没有明确时会保留待确认，不自动推断。", symbol: "checklist")
        }
        ForEach(w.document.analysis.tasks) { task in
          HStack(alignment: .top, spacing: 14) {
            Button {
              w.toggleTask(task.id)
            } label: {
              Image(
                systemName: w.document.completed.contains(task.id)
                  ? "checkmark.circle.fill" : "circle"
              ).font(.system(size: 23))
            }.buttonStyle(.plain).disabled(w.busy)
            VStack(alignment: .leading, spacing: 10) {
              HStack {
                Text(task.title).font(.system(size: 15, weight: .semibold)).strikethrough(
                  w.document.completed.contains(task.id))
                Spacer()
                Text(task.category).font(.caption).foregroundStyle(.secondary)
              }
              Text(task.detail).font(.callout).foregroundStyle(.secondary)
              HStack(spacing: 22) {
                Label(
                  task.ownerID == nil ? "负责人待确认" : w.document.speaker(task.ownerID),
                  systemImage: "person")
                Label(task.deadline ?? "期限待确认", systemImage: "calendar")
              }.font(.caption)
              sourceButtons(task.sourceIDs)
            }
          }.padding(18).background(VTStyle.soft).clipShape(RoundedRectangle(cornerRadius: 10))
        }
      }.padding(28).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity)
    }
  }
  private var inspector: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Text("原文依据").font(.headline)
          Spacer()
          Button {
            w.sourceIDs = []
            w.selectedNode = nil
          } label: {
            Image(systemName: "xmark")
          }.buttonStyle(.plain)
        }
        if let node = w.document.analysis.graph.nodes.first(where: { $0.id == w.selectedNode }) {
          Text(node.title).font(.title3.weight(.semibold))
          Text(node.detail).font(.callout).lineSpacing(6).textSelection(.enabled)
          Button("编辑此节点并保护观点图") { editNode = node }.disabled(w.locked)
          Divider()
        }
        ForEach(w.document.sources(w.sourceIDs)) { row in
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Text(w.document.speaker(row.speakerID))
              Spacer()
              Button(w.document.timeLabel(row)) { w.play(row) }
            }.font(.caption).foregroundStyle(.secondary)
            Text(row.text).font(.system(size: 14)).lineSpacing(6).textSelection(.enabled)
            Button("在逐字稿中查看") { w.page = "原文" }.font(.caption)
            Divider()
          }
        }
      }.padding(20)
    }.background(.background)
  }
  private func sourceButtons(_ ids: [String]) -> some View {
    HStack(spacing: 10) {
      ForEach(w.document.sources(ids).prefix(6)) { row in
        Button {
          w.reveal([row.id])
          w.page = "原文"
        } label: {
          Label(w.document.timeLabel(row), systemImage: "text.quote").font(.system(size: 11))
        }.buttonStyle(.borderless)
      }
    }
  }
  private var exportPageName: String { w.page == "行动" ? "待办清单" : w.page }
  private var exportText: String { w.document.pageText(w.page, disputes: w.onlyDisputes) }

  private func exportTextFile(ext: String = "md") {
    let panel = NSSavePanel()
    panel.nameFieldStringValue =
      VTExporter.filename(w.document.title + "-" + exportPageName, ext: ext)
    if panel.runModal() == .OK, let url = panel.url {
      do { try exportText.write(to: url, atomically: true, encoding: .utf8) } catch {
        w.issue = "导出失败，请检查文件权限"
      }
    }
  }
  private func exportGraph() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = VTExporter.filename(w.document.title + "-观点图", ext: "svg")
    if panel.runModal() == .OK, let url = panel.url {
      do {
        try VTLayout.make(w.document.analysis.graph).svg(w.document).write(
          to: url, atomically: true, encoding: .utf8)
      } catch { w.issue = "导出失败" }
    }
  }
  private func chooseImport() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.message = "选择旧版会议资料总目录。原目录不修改，音频会复制到新资料库。"
    if panel.runModal() == .OK, let url = panel.url { w.importLegacy(url) }
  }
  private func restoreTextBackup() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.message = "恢复文字、图形和任务，作为独立会议副本；此备份不包含音频。"
    if panel.runModal() == .OK, let url = panel.url {
      do {
        let data = try Data(contentsOf: url)
        guard data.count < 50_000_000 else {
          w.issue = "备份文件过大"
          return
        }
        var doc = try JSONDecoder().decode(VTDocument.self, from: data)
        guard doc.version <= 1 else {
          w.issue = "备份来自更新版本，请更新应用"
          return
        }
        doc.id = UUID().uuidString
        doc.title += "（文字恢复）"
        doc.audio = []
        doc.cache = [:]
        doc.capture = "无关联录音"
        doc.trashed = false
        doc.importID = nil
        w.document = doc
        w.recordState = doc.capture
        w.sourceIDs = []
        w.selectedNode = nil
        w.filterSpeaker = nil
        w.page = "总览"
        w.save()
      } catch { w.issue = "备份格式不正确，未改动现有会议" }
    }
  }
  private func importTranscript() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.plainText, .text]
    if panel.runModal() == .OK, let url = panel.url {
      do {
        let text = try String(contentsOf: url, encoding: .utf8)
        guard text.count < 500000 else {
          w.issue = "文件过大，请分段导入"
          return
        }
        w.create()
        w.document.title = url.deletingPathExtension().lastPathComponent
        w.document.timing = "sequence"
        w.document.utterances = text.components(separatedBy: .newlines).filter {
          !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }.enumerated().map {
          VTUtterance(
            id: UUID().uuidString, start: Double($0.offset), end: Double($0.offset + 1),
            speakerID: nil, text: $0.element)
        }
        w.status = "已导入文本。无音频时间信息的行使用顺序标记，非真实会议时间"
        w.save()
      } catch { w.issue = "无法读取UTF-8文字文件" }
    }
  }
}
