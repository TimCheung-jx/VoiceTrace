import Foundation

extension VTDocument {
  var transcriptText: String {
    utterances.map { "[" + timeLabel($0) + "] " + speaker($0.speakerID) + "：" + $0.text }.joined(
      separator: "\n\n")
  }
  var overviewText: String {
    let summary =
      "录音时长：" + vtTime(audio.reduce(0) { $0 + $1.duration })
      + "\n原文：\(utterances.count)段；已区分声音：\(speakers.count)位"
    let highlights = analysis.minutes.prefix(3).map {
      "## " + $0.category + " · " + $0.title + "\n" + $0.detail
    }.joined(separator: "\n\n")
    return summary + (highlights.isEmpty ? "\n\n尚未生成会议摘要。" : "\n\n" + highlights)
      + "\n\n待办：\(analysis.tasks.count)项；分歧：\(analysis.disputes.count)项；章节：\(analysis.chapters.count)项"
  }
  func pageText(_ page: String, disputes: Bool = false) -> String {
    switch page {
    case "总览": return overviewText
    case "原文": return transcriptText
    case "观点图": return plain(disputes ? .disputes : .graph)
    case "会议纪要": return plain(.minutes)
    case "行动": return plain(.tasks)
    case "笔记": return notes
    default: return ""
    }
  }
}
