import AppKit
import SwiftUI

struct VTDraftsView: View {
  @ObservedObject var w: VTWorkspace
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("未定稿（\(w.document.unfinished?.count ?? 0)段）").font(.title2.weight(.semibold))
        Spacer()
        Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      Text("识别中断前的临时文字保留在本机，尚未计入正式原文或AI整理。展开片段后查看，关闭此窗口即可继续阅读原文。")
        .font(.callout).foregroundStyle(.secondary)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          ForEach(Array((w.document.unfinished ?? []).enumerated()), id: \.element.id) {
            index, draft in
            DisclosureGroup {
              Text(draft.text).font(.system(size: 14)).lineSpacing(6).textSelection(.enabled).frame(
                maxWidth: .infinity, alignment: .leading
              ).padding(.top, 8)
            } label: {
              Text("片段\(index + 1) · " + String(draft.text.prefix(45))).lineLimit(2)
            }.padding(14).background(Color.orange.opacity(0.06)).clipShape(
              RoundedRectangle(cornerRadius: 9))
          }
        }
      }
    }.padding(24).frame(width: 690, height: 500).background(Color(nsColor: .windowBackgroundColor))
      .tint(VTStyle.accent)
  }
}
struct VTStartupInfoView: View {
  @ObservedObject var w: VTWorkspace
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("最近一次录音启动诊断").font(.title2)
        Spacer()
        Button("关闭") { dismiss() }
      }
      Text("仅包含阶段、相对耗时和数字错误码；没有录音、会议内容或密钥。录音先启动，诊断文件在后台保存。")
        .font(.caption).foregroundStyle(.secondary)
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(Array(w.startupTrace.events.enumerated()), id: \.offset) { _, event in
            HStack {
              Text(event.label).font(.system(size: 13))
              Spacer()
              Text("\(event.milliseconds) ms").monospacedDigit()
              if event.code != 0 { Text("代码 \(event.code)").foregroundStyle(.orange) }
            }
          }
        }
      }
      Button("导出诊断文件…") {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "VoiceTrace-启动诊断.json"
        if panel.runModal() == .OK, let url = panel.url {
          do { try JSONEncoder().encode(w.startupTrace).write(to: url, options: .atomic) } catch {
            w.issue = "诊断文件导出失败"
          }
        }
      }
    }.padding(24).frame(width: 650, height: 480).background(Color(nsColor: .windowBackgroundColor))
  }
}
