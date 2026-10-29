import Foundation

// 旧语音底层测试入口所需的安全诊断接口，不依赖旧整理控制器。
enum ConnectionDiagnostics {
  static func server(_ header: [String: Any]) -> String {
    let raw = header["error_code"] as? String ?? "unknown"
    let code =
      raw.range(of: "^[A-Za-z0-9_.:-]{1,96}$", options: .regularExpression) != nil ? raw : "unknown"
    return "识别服务拒绝任务（\(code)），请检查地域、模型权限和额度"
  }
}
