import Foundation
struct AppError: LocalizedError { let message: String; var errorDescription: String? { message }; init(_ message: String) { self.message = message } }
struct Sentence: Codable, Identifiable { var id = UUID().uuidString; var start: Double; var end: Double; var text: String; var speaker: String = "待区分发言人" }
struct Recording: Codable, Identifiable { var id = UUID().uuidString; var path: String; var offset: Double; var duration: Double }
struct Meeting: Codable, Identifiable { var id = UUID().uuidString; var title = "新会议"; var created = Date(); var sentences: [Sentence] = []; var recordings: [Recording] = []; var notes = ""; var summary = ""; var chapters = ""; var tree = ""; var todos = ""; var disagreements:String? = nil }
enum Wire {
 static func command(_ action: String, id: String, model: String = "fun-asr-realtime") -> [String: Any] {
  let payload: [String: Any] = action == "run-task" ? ["task_group":"audio", "task":"asr", "function":"recognition", "model":model, "parameters":["format":"pcm", "sample_rate":16000, "language_hints":["zh"], "heartbeat":true], "input":[:]] : ["input":[:]]
  return ["header":["action":action,"task_id":id,"streaming":"duplex"],"payload":payload]
 }
 static func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
 static func object(_ data: Data) throws -> [String:Any] { guard let value = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw AppError("服务返回了无法识别的数据") }; return value }
 static func sentence(_ object: [String: Any], offset: Double) -> Sentence? {
  guard object["heartbeat"] as? Bool != true, let text = object["text"] as? String, !text.isEmpty else { return nil }
  let start = (object["begin_time"] as? NSNumber)?.doubleValue ?? 0
  let end = (object["end_time"] as? NSNumber)?.doubleValue ?? start
  let speaker = (object["speaker_id"] as? NSNumber).map { "本段发言人\($0.intValue + 1)" } ?? "待区分发言人"
  return Sentence(start:offset+start/1000,end:offset+end/1000,text:text,speaker:speaker)
 }
 static func wavHeader(bytes: UInt32) -> Data {
  var d = Data(); func ascii(_ s:String) { d.append(s.data(using:.ascii)!) }; func u32(_ n:UInt32) { var v=n.littleEndian; withUnsafeBytes(of:&v){ d.append(contentsOf:$0) } }; func u16(_ n:UInt16) { var v=n.littleEndian; withUnsafeBytes(of:&v){ d.append(contentsOf:$0) } }
  ascii("RIFF"); u32(bytes+36); ascii("WAVEfmt "); u32(16); u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16); ascii("data"); u32(bytes); return d
 }
 static func time(_ seconds:Double) -> String { let t=max(0,Int(seconds)); return String(format:"%02d:%02d",t/60,t%60) }
 static func validateWorkspace(_ s:String) -> Bool { !s.isEmpty && s.range(of:"^[a-zA-Z0-9-]+$",options:.regularExpression) != nil }
}
