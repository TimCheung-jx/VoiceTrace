import SwiftUI

struct VTRecognitionBar: View {
  @ObservedObject var w: VTWorkspace
  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { tick in
      HStack(spacing: 12) {
        Label(w.level < 0.02 ? "输入较弱或静音" : "检测到声音", systemImage: "mic")
        ProgressView(value: Double(w.level)).frame(width: 65)
        Divider().frame(height: 14)
        Circle().fill(w.recognition.phase == .live ? Color.green : Color.orange).frame(
          width: 6, height: 6)
        Text(w.recognition.phase.rawValue).fontWeight(.medium)
        if let last = w.recognition.lastResult {
          Text("最近回字：\(max(0,Int(tick.date.timeIntervalSince(last))))秒前")
        } else {
          Text("尚未返回文字")
        }
        Spacer()
        Button("重新连接识别") { w.recorder.reconnect() }.disabled(
          w.recognition.phase == .connecting || w.recognition.phase == .credentials || w.preparing)
      }.font(.system(size: 11)).foregroundStyle(.secondary)
    }.padding(.horizontal, 24).padding(.bottom, 12)
  }
}

/// 时间只驱动声波的流动；幅度取自真实麦克风电平，静音时保持低幅呼吸。
struct VTRecordingWaveform: View {
  let level: Float
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    HStack(spacing: 9) {
      Circle().fill(Color.red).frame(width: 7, height: 7)
      Text("录音中").font(.system(size: 12, weight: .semibold)).foregroundStyle(VTStyle.accent)
      TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { context in
        Canvas { drawing, size in
          let phase = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 4
          let loudness = max(0, min(1, Double(level)))
          let count = 24
          for index in 0..<count {
            let x = Double(index) / Double(count - 1)
            let envelope = 0.25 + 0.75 * pow(sin(x * .pi), 1.3)
            let ripple = 0.35 + 0.65 * abs(sin(phase + x * 8))
            let height = max(3, min(size.height, (5 + loudness * 30) * envelope * ripple))
            let rect = CGRect(
              x: x * (size.width - 3), y: (size.height - height) / 2, width: 2.4, height: height)
            drawing.fill(Path(roundedRect: rect, cornerRadius: 1.2), with: .color(VTStyle.accent))
          }
        }
      }.frame(width: 92, height: 30)
    }.padding(.horizontal, 12).padding(.vertical, 7)
      .background(VTStyle.accent.opacity(0.07)).clipShape(Capsule())
      .accessibilityElement(children: .ignore).accessibilityLabel("正在录音，麦克风声波")
      .accessibilityValue("音量\(Int(max(0,min(1,level))*100))%")
  }
}
