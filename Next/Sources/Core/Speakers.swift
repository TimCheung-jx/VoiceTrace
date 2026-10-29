import Foundation

extension VTDocument {
  /// 只有识别服务确实提供不同声音编号时，才创建匿名发言人。
  /// track必须包含录音段标识，不能假定不同录音段的speaker_id相同就属于同一人。
  @discardableResult mutating func registerVoice(track: String) -> String {
    let id = vtID("voice|" + track)
    if speakers.contains(where: { $0.id == id }) { return id }
    let number = max(speakers.count, speakers.compactMap { $0.placeholderNumber }.max() ?? 0) + 1
    speakers.append(VTSpeaker(id: id, name: "发言人\(number)", placeholderNumber: number))
    return id
  }

  mutating func nameSpeaker(_ id: String, name: String) throws {
    guard let index = speakers.firstIndex(where: { $0.id == id }) else {
      throw VTError.message("未找到这个发言人，未修改会议")
    }
    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty, clean.count <= 60 else {
      throw VTError.message("请输入1至60字的姓名或身份")
    }
    speakers[index].name = clean
    // 身份引用保持不变，图形、原文与任务标签随名称一起更新。
    cache = [:]
    invalidate()
  }
}

/// 用户离开最新位置后，新增文字不强行打断阅读。
struct VTTranscriptFollow {
  var following = true
  var unread = 0
  mutating func userScrolled() { following = false }
  mutating func receivedFinal() { if !following { unread += 1 } }
  mutating func returnToLatest() {
    following = true
    unread = 0
  }
}
