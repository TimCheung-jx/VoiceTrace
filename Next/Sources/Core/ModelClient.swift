import Foundation

struct VTModelConfig {
  var baseURL: String
  var model: String
  var jsonMode: Bool
}
enum VTModelClient {
  typealias Transport = (URLRequest) async throws -> (Data, Int)
  static func request(
    document: VTDocument, config: VTModelConfig, key: String, transport: Transport
  ) async throws -> String {
    var base = config.baseURL
    while base.hasSuffix("/") { base.removeLast() }
    guard let url = URL(string: base + "/chat/completions"), url.scheme == "https", url.host != nil,
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, !key.isEmpty
    else { throw VTError.message("整理服务地址或密钥未配置") }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 120
    request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var body: [String: Any] = [
      "model": config.model, "stream": false, "max_tokens": 8192,
      "messages": [
        ["role": "system", "content": VTAnalyzer.prompt],
        ["role": "user", "content": try VTAnalyzer.source(document)],
      ],
    ]
    if config.jsonMode { body["response_format"] = ["type": "json_object"] }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, status) = try await transport(request)
    guard (200...299).contains(status) else {
      throw VTError.message(
        status == 401 || status == 403
          ? "整理服务鉴权失败，请检查当前服务的密钥和权限"
          : status == 429 ? "整理服务限流或额度不足，请稍后重试" : "整理服务请求失败（HTTP \(status)），原有成果已保留")
    }
    guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let choices = obj["choices"] as? [[String: Any]], let choice = choices.first
    else { throw VTError.message("服务商返回格式不符合 Chat Completions 协议") }
    if choice["finish_reason"] as? String == "length" {
      throw VTError.message("模型输出被截断，请缩短片段或调整模型")
    }
    guard let message = choice["message"] as? [String: Any],
      let content = message["content"] as? String,
      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw VTError.message("模型返回了空内容，旧成果已保留") }
    return content
  }
}
