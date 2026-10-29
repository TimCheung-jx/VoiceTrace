import SwiftUI

struct VTSettings: View {
  @ObservedObject var w: VTWorkspace
  @Environment(\.dismiss) private var dismiss
  @State private var speech = SpeechProfile()
  @State private var text = TextProfile()
  @State private var speechKey = ""
  @State private var textKey = ""
  @State private var error = ""
  @State private var jsonMode = true
  @State private var liveAnalysis = true
  @State private var finalAnalysis = true
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("服务与隐私").font(.title2.weight(.semibold))
      Text("录音及资料保存在本机。识别和整理会发送至您选择的服务。密钥保存在钥匙串，留空保持原密钥。").font(.callout).foregroundStyle(
        .secondary)
      Form {
        Section("语音识别 · 百炼") {
          Picker(
            "已存配置",
            selection: Binding(
              get: { speech.id },
              set: { id in
                if let p = w.settings.speech.first(where: { $0.id == id }) {
                  speech = p
                  speechKey = ""
                }
              })
          ) { ForEach(w.settings.speech) { p in Text(p.name).tag(p.id) } }
          TextField("配置名称", text: $speech.name)
          Picker("地域", selection: $speech.region) {
            Text("北京").tag("cn-beijing")
            Text("新加坡").tag("ap-southeast-1")
          }
          TextField("Workspace ID", text: $speech.workspace)
          TextField("实时模型", text: $speech.realtimeModel)
          TextField("会后模型", text: $speech.fileModel)
          Picker(
            "停顿后断句",
            selection: Binding(
              get: { speech.sentenceSilence ?? 800 }, set: { speech.sentenceSilence = $0 })
          ) {
            Text("快速 · 0.6秒").tag(600)
            Text("均衡 · 0.8秒").tag(800)
            Text("长句 · 1.3秒").tag(1300)
          }
          Toggle(
            "轻声识别（可能增加环境噪音转写）",
            isOn: Binding(get: { speech.quietSpeech ?? false }, set: { speech.quietSpeech = $0 }))
          SecureField("API Key（留空保持）", text: $speechKey)
        }
        Section("会议整理 · 独立配置") {
          Picker(
            "已存配置",
            selection: Binding(
              get: { text.id },
              set: { id in
                if let p = w.settings.texts.first(where: { $0.id == id }) {
                  text = p
                  textKey = ""
                }
              })
          ) { ForEach(w.settings.texts) { p in Text(p.name).tag(p.id) } }
          TextField("配置名称", text: $text.name)
          Picker("接口", selection: $text.provider) {
            Text("DeepSeek 官方").tag("deepseek")
            Text("兼容 Chat Completions").tag("compatible")
          }
          TextField("基础地址", text: $text.baseURL)
          TextField("模型", text: $text.model)
          SecureField("API Key（留空保持）", text: $textKey)
          Toggle("服务支持 JSON 输出模式", isOn: $jsonMode)
          Toggle("录音时每45秒整理草稿", isOn: $liveAnalysis)
          Toggle("结束录音后自动整理", isOn: $finalAnalysis)
        }
      }.formStyle(.grouped)
      Button("保存配置并用虚构会议验证完整整理") {
        do {
          w.jsonMode = jsonMode
          w.automatic = liveAnalysis
          w.finalAutomatic = finalAnalysis
          try w.saveSettings(speech: speech, text: text, speechKey: speechKey, textKey: textKey)
          speechKey = ""
          textKey = ""
          dismiss()
          w.validateWithCloud()
        } catch { self.error = error.localizedDescription }
      }.disabled(w.locked)
      Text("该验证会创建独立的虚构会议并调用所选整理API，可能产生少量费用；不发送您的真实会议。").font(.caption).foregroundStyle(.secondary)
      if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
      HStack {
        Button("另存为新配置") {
          speech.id = UUID().uuidString
          speech.name += " 副本"
          speech.legacyScope = nil
          text.id = UUID().uuidString
          text.name += " 副本"
          text.legacyScope = nil
        }
        Spacer()
        Button("取消") { dismiss() }
        Button("保存设置") {
          do {
            w.jsonMode = jsonMode
            w.automatic = liveAnalysis
            w.finalAutomatic = finalAnalysis
            try w.saveSettings(speech: speech, text: text, speechKey: speechKey, textKey: textKey)
            speechKey = ""
            textKey = ""
            dismiss()
          } catch { self.error = error.localizedDescription }
        }.buttonStyle(.borderedProminent).disabled(w.locked)
      }
    }.padding(25).frame(width: 660, height: 760).background(Color(nsColor: .windowBackgroundColor))
      .onAppear {
        speech = w.settings.activeSpeech
        text = w.settings.activeText
        jsonMode = w.jsonMode
        liveAnalysis = w.automatic
        finalAnalysis = w.finalAutomatic
      }
  }
}
struct VTTranscriptEditor: View {
  @ObservedObject var w: VTWorkspace
  let row: VTUtterance
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var speaker = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("修订原文").font(.title2)
      Text("保留修改前版本。改动后，相关整理成果会标记为过期。").font(.callout).foregroundStyle(.secondary)
      TextField("发言人名称；不知道可留空", text: $speaker)
      TextEditor(text: $text).font(.body)
      HStack {
        Spacer()
        Button("取消") { dismiss() }
        Button("保存修订") {
          guard let index = w.document.utterances.firstIndex(where: { $0.id == row.id }) else {
            return
          }
          let old = w.document
          w.document.utterances[index].text = text
          let label = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
          if label.isEmpty {
            w.document.utterances[index].speakerID = nil
          } else {
            let id = w.document.speakers.first { $0.name == label }?.id ?? UUID().uuidString
            if !w.document.speakers.contains(where: { $0.id == id }) {
              w.document.speakers.append(VTSpeaker(id: id, name: label))
            }
            w.document.utterances[index].speakerID = id
          }
          w.document.invalidate()
          if w.save(reason: "逐字稿人工纠错") { dismiss() } else { w.document = old }
        }.buttonStyle(.borderedProminent).disabled(
          text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(25).frame(width: 600, height: 440).onAppear {
      text = row.text
      speaker = row.speakerID == nil ? "" : w.document.speaker(row.speakerID)
    }
  }
}
struct VTNodeEditor: View {
  @ObservedObject var w: VTWorkspace
  let node: VTNode
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var text = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("修订观点节点").font(.title2)
      Text("保存前备份，观点图会被人工保护；您可在导出菜单解除保护。").font(.callout).foregroundStyle(.secondary)
      TextField("标题", text: $title)
      TextEditor(text: $text)
      HStack {
        Spacer()
        Button("取消") { dismiss() }
        Button("保存并保护") {
          guard let i = w.document.analysis.graph.nodes.firstIndex(where: { $0.id == node.id })
          else { return }
          w.document.analysis.graph.nodes[i].title = title
          w.document.analysis.graph.nodes[i].detail = text
          w.document.protected.insert("graph")
          if w.save(reason: "观点图人工修订") { dismiss() }
        }.buttonStyle(.borderedProminent).disabled(title.isEmpty || text.isEmpty)
      }
    }.padding(25).frame(width: 600, height: 440).onAppear {
      title = node.title
      text = node.detail
    }
  }
}
struct VTHistoryView: View {
  @ObservedObject var w: VTWorkspace
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("修订历史").font(.title2)
      Text("恢复文字、图形及任务时，仍保留现有录音文件和当前版本备份。").foregroundStyle(.secondary)
      List {
        ForEach(w.history, id: \.0) { row in
          DisclosureGroup(row.1) {
            Text(row.2.created, style: .date)
            Text(row.2.plain(.minutes)).font(.callout).lineLimit(8)
            Button("恢复此版本") {
              let audio = w.document.audio
              let cache = w.document.cache
              w.document = row.2
              w.document.audio = audio
              w.document.cache = cache
              w.document.invalidate()
              if w.save(reason: "恢复历史前版本") { dismiss() }
            }
          }
        }
      }
      HStack {
        Spacer()
        Button("完成") { dismiss() }
      }
    }.padding(25).frame(width: 700, height: 540)
  }
}
struct VTAskView: View {
  @ObservedObject var w: VTWorkspace
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("AI 会议问答").font(.title2)
        Spacer()
        Button("关闭") {
          w.cancelQuestion()
          dismiss()
        }
      }
      Text("依据本次会议原文回答；长会议最多发送3万字符片段，请核对来源。问题和回答保留在本次会议的对话中。")
        .font(.caption).foregroundStyle(.secondary)
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 18) {
            if (w.document.conversation ?? []).isEmpty {
              Text("输入问题，或选择下方快捷问题。").foregroundStyle(.secondary)
            }
            ForEach(w.document.conversation ?? []) { turn in
              VStack(alignment: .leading, spacing: 12) {
                HStack {
                  Spacer(minLength: 60)
                  Text(turn.question).textSelection(.enabled).padding(13).background(
                    VTStyle.accent.opacity(0.09)
                  ).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                HStack(alignment: .top) {
                  VStack(alignment: .leading, spacing: 7) {
                    Text("声迹 AI").font(.caption.weight(.semibold)).foregroundStyle(VTStyle.accent)
                    if turn.phase == .waiting {
                      HStack {
                        ProgressView().controlSize(.small)
                        Text("正在回复…")
                      }.font(.callout).foregroundStyle(.secondary)
                    } else {
                      Text(
                        (try? AttributedString(
                          markdown: turn.answer.isEmpty ? "本次请求已取消，可重新提问。" : turn.answer,
                          options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                          ?? AttributedString(turn.answer)
                      )
                      .font(.system(size: 14)).lineSpacing(6).textSelection(.enabled)
                      if turn.phase == .failed || turn.phase == .cancelled {
                        Button("重新填入问题") { w.question = turn.question }
                      }
                    }
                  }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(
                    VTStyle.soft
                  ).clipShape(RoundedRectangle(cornerRadius: 12))
                  Spacer(minLength: 25)
                }
              }.id(turn.id)
            }
            Color.clear.frame(height: 1).id("chat-latest")
          }.padding(.vertical, 6)
        }
        .onChange(of: w.document.conversation) { _ in
          DispatchQueue.main.async { proxy.scrollTo("chat-latest", anchor: .bottom) }
        }
        .onAppear { DispatchQueue.main.async { proxy.scrollTo("chat-latest", anchor: .bottom) } }
      }
      TextField("输入问题，按回车或点击提问", text: $w.question).textFieldStyle(.roundedBorder).onSubmit {
        Task { await w.ask() }
      }
      HStack {
        ForEach(["本次会议有哪些决定？", "主要分歧是什么？", "接下来需要做什么？"], id: \.self) { prompt in
          Button(prompt) { w.question = prompt }
        }
      }.font(.caption)
      HStack {
        if !(w.document.conversation ?? []).isEmpty {
          Button("导出对话 PDF") {
            VTExporter.exportPDF(
              title: w.document.title + "-AI问答", text: w.document.conversationText)
          }
        }
        Spacer()
        if w.asking { Button("取消请求") { w.cancelQuestion() } }
        Button("提问") { Task { await w.ask() } }.buttonStyle(.borderedProminent).disabled(
          w.asking || w.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || w.document.utterances.isEmpty)
      }
    }.padding(24).frame(width: 720, height: 620).background(Color(nsColor: .windowBackgroundColor))
      .tint(VTStyle.accent)
  }
}
