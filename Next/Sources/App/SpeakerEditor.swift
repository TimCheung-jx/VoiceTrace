import SwiftUI

struct VTSpeakerEditor: View {
  @ObservedObject var w: VTWorkspace
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("确认发言人身份").font(.title2.weight(.semibold))
      Text("发言人编号代表已区分的声音，不代表真实身份。修改名称会同步到该编号的全部原文、观点标签和任务负责人，并保留修订历史。")
        .font(.callout).foregroundStyle(.secondary)
      ScrollView {
        VStack(spacing: 14) {
          ForEach(w.document.speakers) { speaker in
            VTSpeakerNameRow(w: w, speaker: speaker)
          }
          if w.document.speakers.isEmpty {
            Text("当前语音服务没有提供可区分的声音编号，可先使用会后区分发言人，再确认身份。")
              .foregroundStyle(.secondary).padding(.vertical, 25)
          }
        }
      }
      let unknown = w.document.utterances.filter { $0.speakerID == nil }.count
      if unknown > 0 {
        Text("另有\(unknown)段未区分声音的原文，仍显示“未区分发言人”；可在逐段纠错中人工指定身份。")
          .font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Spacer()
        Button("完成") { dismiss() }.buttonStyle(.borderedProminent)
      }
    }.padding(26).frame(width: 650, height: 490)
      .background(Color(nsColor: .windowBackgroundColor)).tint(VTStyle.accent)
  }
}
private struct VTSpeakerNameRow: View {
  @ObservedObject var w: VTWorkspace
  let speaker: VTSpeaker
  @State private var name = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(speaker.placeholderNumber.map { "发言人\($0)" } ?? "已记录的发言人")
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        if let sample = w.document.utterances.first(where: { $0.speakerID == speaker.id }) {
          Button {
            w.play(sample)
          } label: {
            Label("回听辨认", systemImage: "play.circle")
          }
          .buttonStyle(.borderless)
        }
      }
      HStack {
        TextField("输入姓名或身份，例如：张经理", text: $name)
          .textFieldStyle(.roundedBorder).onSubmit { apply() }
        Button("应用到此发言人的全部内容") { apply() }
          .disabled(
            w.locked || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || name.trimmingCharacters(in: .whitespacesAndNewlines)
                == w.document.speaker(speaker.id)
          )
      }
    }.padding(15).background(VTStyle.soft).clipShape(RoundedRectangle(cornerRadius: 10))
      .onAppear { name = w.document.speaker(speaker.id) }
  }
  private func apply() { _ = w.renameSpeaker(speaker.id, name: name) }
}
