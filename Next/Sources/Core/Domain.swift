import CryptoKit
import Foundation

enum VTError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    if case .message(let s) = self { return s }
    return nil
  }
}
func vtCanonical<T: Encodable>(_ value: T) throws -> Data {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  return try encoder.encode(value)
}
func vtID(_ text: String) -> String {
  SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
}
func vtTime(_ time: Double) -> String {
  let t = max(0, Int(time))
  return t >= 3600
    ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
    : String(format: "%02d:%02d", t / 60, t % 60)
}
struct VTSpeaker: Codable, Identifiable, Equatable {
  var id: String
  var name: String
  var placeholderNumber: Int? = nil
}
struct VTUtterance: Codable, Identifiable, Equatable {
  var id: String
  var start: Double
  var end: Double
  var speakerID: String?
  var text: String
}
struct VTAudio: Codable, Identifiable, Equatable {
  var id = UUID().uuidString
  var path: String
  var offset: Double
  var duration: Double
}
enum VTNodeKind: String, Codable, CaseIterable {
  case topic, position, reason, response, decision, open
  var label: String {
    switch self {
    case .topic: return "议题"
    case .position: return "观点"
    case .reason: return "理由"
    case .response: return "回应"
    case .decision: return "决定"
    case .open: return "待确认"
    }
  }
}
struct VTNode: Codable, Identifiable, Equatable {
  var id: String
  var kind: VTNodeKind
  var title: String
  var detail: String
  var speakerID: String?
  var sourceIDs: [String]
}
struct VTEdge: Codable, Identifiable, Equatable {
  var from: String
  var to: String
  var relation: String
  var id: String { from + "|" + to + "|" + relation }
}
struct VTGraph: Codable, Equatable {
  var nodes: [VTNode] = []
  var edges: [VTEdge] = []
}
struct VTMinute: Codable, Identifiable, Equatable {
  var id: String
  var category: String
  var title: String
  var detail: String
  var sourceIDs: [String]
}
struct VTDispute: Codable, Identifiable, Equatable {
  var id: String
  var title: String
  var category: String
  var positionIDs: [String]
  var outcome: String
  var sourceIDs: [String]
}
struct VTTask: Codable, Identifiable, Equatable {
  var id: String
  var title: String
  var detail: String
  var ownerID: String?
  var deadline: String?
  var category: String
  var sourceIDs: [String]
}
struct VTChapter: Codable, Identifiable, Equatable {
  var id: String
  var title: String
  var detail: String
  var sourceIDs: [String]
}
enum VTSection: String, CaseIterable, Codable {
  case minutes, graph, disputes, tasks, chapters
  var label: String {
    switch self {
    case .minutes: return "纪要"
    case .graph: return "观点图"
    case .disputes: return "分歧"
    case .tasks: return "行动事项"
    case .chapters: return "章节"
    }
  }
}
enum VTPhase: String, Codable {
  case idle, working, ready, failed, stale
  var label: String {
    switch self {
    case .idle: return "尚未生成"
    case .working: return "正在整理"
    case .ready: return "可用 · 请核对"
    case .failed: return "生成失败"
    case .stale: return "原文已更新"
    }
  }
}
struct VTArtifactState: Codable, Equatable {
  var phase: VTPhase = .idle
  var message = ""
  var updated: Date?
  var revision: String?
}
struct VTAnalysis: Codable, Equatable {
  var graph = VTGraph()
  var minutes: [VTMinute] = []
  var disputes: [VTDispute] = []
  var tasks: [VTTask] = []
  var chapters: [VTChapter] = []
  var states: [String: VTArtifactState] = [:]
  var model = ""
  var revision = ""
}
struct VTDocument: Codable, Identifiable, Equatable {
  var timing = "audio"
  var version = 1
  var id = UUID().uuidString
  var title = "未命名会议"
  var created = Date()
  var speakers: [VTSpeaker] = []
  var utterances: [VTUtterance] = []
  var audio: [VTAudio] = []
  var notes = ""
  var analysis = VTAnalysis()
  var cache: [String: VTAnalysis] = [:]
  var completed: Set<String> = []
  var protected: Set<String> = []
  var capture = "未开始"
  var importID: String?
  var legacyText: [String: String]?
  var unfinished: [VTDraft]?
  var draftsNoticeDismissed: Bool?
  var conversation: [VTChatTurn]?
  var trashed = false
  var revision: String {
    vtID(String(decoding: (try? vtCanonical(utterances)) ?? Data(), as: UTF8.self))
  }
  func timeLabel(_ row: VTUtterance) -> String {
    timing == "sequence"
      ? "第\((utterances.firstIndex(where:{$0.id==row.id}) ?? 0)+1)段" : vtTime(row.start)
  }
  func speaker(_ id: String?) -> String {
    guard let index = speakers.firstIndex(where: { $0.id == id }) else { return "未区分发言人" }
    let person = speakers[index]
    if person.name.range(of: "^(本段发言人|发言人)[0-9]+( · 第[0-9]+段)?$", options: .regularExpression)
      != nil
    {
      return "发言人\(person.placeholderNumber ?? (index+1))"
    }
    return person.name
  }
  func sources(_ ids: [String]) -> [VTUtterance] {
    let set = Set(ids)
    return utterances.filter { set.contains($0.id) }
  }
  mutating func invalidate() {
    for section in VTSection.allCases {
      if analysis.states[section.rawValue]?.phase == .ready {
        analysis.states[section.rawValue]?.phase = .stale
      }
    }
  }
  func plain(_ section: VTSection) -> String {
    func refs(_ ids: [String]) -> String {
      sources(ids).map { "[" + timeLabel($0) + "]" }.joined(separator: " ")
    }
    switch section {
    case .minutes:
      return analysis.minutes.map {
        "## " + $0.category + " · " + $0.title + "\n" + $0.detail + "\n" + refs($0.sourceIDs)
      }.joined(separator: "\n\n")
    case .graph:
      return analysis.graph.nodes.map {
        "## " + $0.kind.label + " · " + $0.title + "\n" + speaker($0.speakerID) + "\n" + $0.detail
          + "\n" + refs($0.sourceIDs)
      }.joined(separator: "\n\n")
    case .disputes:
      return analysis.disputes.map { d in
        "## " + d.title + " · " + d.category + "\n"
          + analysis.graph.nodes.filter { d.positionIDs.contains($0.id) }.map {
            speaker($0.speakerID) + "：" + $0.detail
          }.joined(separator: "\n") + "\n" + d.outcome + "\n" + refs(d.sourceIDs)
      }.joined(separator: "\n\n")
    case .tasks:
      // 分开确定可选值及各行，避免旧Swift编译器对长字符串表达式求解超时。
      let rows: [String] = analysis.tasks.map { task -> String in
        let mark = completed.contains(task.id) ? "[x] " : "[ ] "
        let owner = task.ownerID == nil ? "待确认" : speaker(task.ownerID)
        let deadline = task.deadline ?? "待确认"
        let heading = mark + task.title
        let attribution = "负责人：\(owner)；期限：\(deadline)"
        return [heading, task.detail, attribution, refs(task.sourceIDs)].joined(separator: "\n")
      }
      return rows.joined(separator: "\n\n")
    case .chapters:
      return analysis.chapters.map { $0.title + "\n" + $0.detail + "\n" + refs($0.sourceIDs) }
        .joined(separator: "\n\n")
    }
  }
}
