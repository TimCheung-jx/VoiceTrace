import Foundation

struct VTRecognitionHealth: Equatable {
  enum Phase: String {
    case idle = "未连接"
    case credentials = "读取服务凭据"
    case connecting = "连接中"
    case live = "实时识别中"
    case retrying = "正在重连"
    case offline = "仅本地录音"
    case ended = "识别已结束"
  }
  var phase: Phase = .idle
  var detail = ""
  var connectedAt: Date?
  var lastResult: Date?
  var lastVoice: Date?
  var attempt = 0
  func stalled(at now: Date) -> Bool {
    guard phase == .live, let base = lastResult ?? connectedAt, let voice = lastVoice else {
      return false
    }
    return now.timeIntervalSince(base) >= 30 && now.timeIntervalSince(voice) < 4
  }
}
struct VTDraft: Codable, Identifiable, Equatable {
  var id: String
  var text: String
}

/// 音频线程只将数据交给当前连接；重连后不能继续向已关闭的连接发送。
final class VTPCMRelay {
  private let lock = NSLock()
  private var sink: AsyncStream<Data>.Continuation?
  private var token = ""
  func install(_ next: AsyncStream<Data>.Continuation, token: String) {
    lock.lock()
    let old = sink
    sink = next
    self.token = token
    lock.unlock()
    old?.finish()
  }
  func push(_ data: Data) -> String? {
    lock.lock()
    defer { lock.unlock() }
    if let sink = sink, case .dropped = sink.yield(data) { return token }
    return nil
  }
  func finish() {
    lock.lock()
    let old = sink
    sink = nil
    token = ""
    lock.unlock()
    old?.finish()
  }
}
