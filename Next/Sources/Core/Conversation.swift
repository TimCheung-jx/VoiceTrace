import Foundation

struct VTChatTurn: Codable, Identifiable, Equatable {
  enum Phase: String, Codable { case waiting, answered, failed, cancelled }
  var id = UUID().uuidString
  var question: String
  var answer = ""
  var phase: Phase = .waiting
}
extension VTDocument {
  var conversationText: String {
    (conversation ?? []).map {
      "## 提问\n" + $0.question + "\n\n## 回答\n"
        + ($0.answer.isEmpty ? ($0.phase == .waiting ? "等待回复" : "本次请求未完成") : $0.answer)
    }.joined(separator: "\n\n")
  }
  func followup(_ query: String) -> String {
    let past = (conversation ?? []).filter { $0.phase == .answered }.suffix(6).map {
      "问题：" + String($0.question.prefix(1000)) + "\n回答：" + String($0.answer.prefix(1500))
    }.joined(separator: "\n\n")
    return (past.isEmpty ? "" : "以下近期对话只用于理解追问，事实仍以会议原文为准：\n" + past + "\n\n") + "当前问题：" + query
  }
}

struct VTStartupTrace: Codable {
  struct Event: Codable {
    var stage: String
    var milliseconds: Int
    var code: Int
    var label: String {
      [
        "recognition_connection_error": "识别网络连接错误", "recognition_send_error": "音频发送错误",
        "recognition_timeout": "识别连接超时", "recognition_rejected": "服务商拒绝识别任务",
        "recognition_stalled": "检测到声音但无识别结果", "credentials_unavailable": "服务凭据未能取得",
        "no_audio_buffers": "麦克风未产生音频", "requested": "开始录音请求", "permission_denied": "麦克风权限未允许",
        "permission_ready": "麦克风权限就绪",
        "audio_starting": "正在启动采集",
        "engine_started": "音频引擎已启动", "engine_start_failed": "音频引擎启动失败",
        "local_recording": "本地采集已启动", "first_pcm": "首次采集到音频", "credentials_ready": "服务凭据读取完成",
        "recognition_connected": "识别服务已连接", "first_text": "首次收到识别文字",
        "configuration_stable": "音频配置稳定", "engine_recovering": "正在恢复麦克风",
        "engine_recovered": "麦克风已恢复", "engine_recovery_exhausted": "麦克风恢复次数已达上限",
        "engine_recovery_failed": "麦克风恢复失败", "conversion_error": "音频转换错误",
        "file_write_error": "录音写盘错误", "file_size_limit": "录音文件大小达到上限", "audio_paused": "录音已暂停",
        "audio_stopped": "录音已结束", "capture_failed": "音频采集失败", "startup_buffer_full": "启动识别缓冲已满",
      ][stage] ?? stage
    }
  }
  enum CodingKeys: String, CodingKey { case id, events }
  var id = UUID().uuidString
  var events: [Event] = []
  private var origin = ProcessInfo.processInfo.systemUptime
  static let stages: Set<String> = [
    "recognition_connection_error", "recognition_send_error", "recognition_timeout",
    "recognition_rejected", "recognition_stalled", "credentials_unavailable", "no_audio_buffers",
    "requested", "permission_denied", "permission_ready", "audio_starting",
    "engine_started",
    "engine_start_failed",
    "local_recording", "first_pcm", "credentials_ready", "recognition_connected", "first_text",
    "configuration_stable", "engine_recovering", "engine_recovered", "engine_recovery_exhausted",
    "engine_recovery_failed", "conversion_or_write_error", "conversion_error", "file_write_error",
    "file_size_limit", "audio_paused", "audio_stopped", "capture_failed", "startup_buffer_full",
  ]
  static let failures: Set<String> = [
    "permission_denied", "engine_start_failed", "file_write_error", "engine_recovery_exhausted",
    "capture_failed", "file_size_limit",
  ]
  var hasFailure: Bool { events.contains { Self.failures.contains($0.stage) } }
  @discardableResult mutating func record(_ stage: String, code: Int = 0) -> Bool {
    guard Self.stages.contains(stage) else { return false }
    let event = Event(
      stage: stage,
      milliseconds: max(0, Int((ProcessInfo.processInfo.systemUptime - origin) * 1000)), code: code)
    if events.count < 32 {
      events.append(event)
    } else {
      guard Self.failures.contains(stage) || stage == "audio_stopped" || stage == "audio_paused"
      else { return false }
      // 容量用尽也保留最后错误与结束阶段，普通通知不能淹没失败原因。
      if Self.failures.contains(events[31].stage), !Self.failures.contains(stage) {
        events[30] = events[31]
      }
      events[31] = event
    }
    return true
  }

}

final class VTOnce {
  private let lock = NSLock()
  private var used = false
  func claim() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if used { return false }
    used = true
    return true
  }
}
