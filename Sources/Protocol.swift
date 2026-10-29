import Foundation
struct AppError: LocalizedError { let message: String; var errorDescription: String? { message }; init(_ message: String) { self.message = message } }
struct Sentence: Codable, Identifiable { var id = UUID().uuidString; var start: Double; var end: Double; var text: String; var speaker: String = "待区分发言人" }
struct Recording: Codable, Identifiable { var id = UUID().uuidString; var path: String; var offset: Double; var duration: Double }
struct Meeting: Codable, Identifiable { var id = UUID().uuidString; var title = "新会议"; var created = Date(); var sentences: [Sentence] = []; var recordings: [Recording] = []; var notes = ""; var summary = ""; var chapters = ""; var tree = ""; var todos = ""; var disagreements:String? = nil; var captureState:String? = nil; var summaryState:String? = nil; var summaryUpdated:Date? = nil; var summaryThrough:Double? = nil; var summaryModel:String? = nil; var summaryCache:[SummaryCache]? = nil; var protectedSections:[String]? = nil; var aiSuggestion:[String:String]? = nil; var transcriptEdited:Bool? = nil; var completedTasks:[String]? = nil; var segmentSummaries:[[String:String]]? = nil }
enum Wire {
 static func command(_ action: String, id: String, model: String = "fun-asr-realtime", parameters:[String:Any] = [:]) -> [String: Any] {
  let defaults:[String:Any] = ["format":"pcm", "sample_rate":16000, "language_hints":["zh"], "heartbeat":true]
  let payload: [String: Any] = action == "run-task" ? ["task_group":"audio", "task":"asr", "function":"recognition", "model":model, "parameters":defaults.merging(parameters){_,new in new}, "input":[:]] : ["input":[:]]
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

// 恢复只处理本应用的16kHz单声道16位PCM；保留原件，不自动联网。
struct CaptureJournal:Codable {let offset:Double}
struct RecoveryCandidate:Identifiable {
 let meetingID:String
 let title:String
 let pcm:URL
 let bytes:UInt32
 let offset:Double
 var id:String{pcm.path}
 var duration:Double{Double(bytes)/32000}
 var recoveredURL:URL{pcm.deletingPathExtension().appendingPathExtension("recovered.wav")}
 static func scan(root:URL)->[Self]{
  let fm=FileManager.default
  let folders=(try? fm.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? []
  return folders.flatMap{folder -> [Self] in
   guard folder.lastPathComponent != "RecentlyDeleted",let data=try? Data(contentsOf:folder.appendingPathComponent("meeting.json")),let meeting=try? JSONDecoder().decode(Meeting.self,from:data) else{return []}
   let files=(try? fm.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)) ?? []
   return files.compactMap{url in
    guard url.pathExtension=="pcm",url.lastPathComponent.hasPrefix("audio-"),let attributes=try? fm.attributesOfItem(atPath:url.path),let size=attributes[.size] as? NSNumber,size.uint64Value>=2,size.uint64Value<=UInt64(UInt32.max)-44 else{return nil}
    let wav=url.deletingPathExtension().appendingPathExtension("wav")
    let recovered=url.deletingPathExtension().appendingPathExtension("recovered.wav")
    guard !meeting.recordings.contains(where:{$0.path==wav.path || $0.path==recovered.path}) else{return nil}
    let journal=(try? Data(contentsOf:url.appendingPathExtension("capture.json"))).flatMap{try? JSONDecoder().decode(CaptureJournal.self,from:$0)}
    return Self(meetingID:meeting.id,title:meeting.title,pcm:url,bytes:UInt32(size.uint64Value/2*2),offset:journal?.offset ?? meeting.recordings.reduce(0){max($0,$1.offset+$1.duration)})
   }
  }
 }
 func recover() throws -> Recording {
  let fm=FileManager.default
  if fm.fileExists(atPath:recoveredURL.path){
   let data=try Data(contentsOf:recoveredURL,options:.mappedIfSafe)
   guard data.count==Int(bytes)+44,data.prefix(44)==Wire.wavHeader(bytes:bytes) else{throw AppError("恢复文件不完整，请保留原始PCM并检查目录")}
  }else{
   let staging=pcm.deletingLastPathComponent().appendingPathComponent("recovery-"+UUID().uuidString+".tmp")
   guard fm.createFile(atPath:staging.path,contents:Wire.wavHeader(bytes:bytes)) else{throw AppError("无法创建恢复文件")}
   let input=try FileHandle(forReadingFrom:pcm);defer{try? input.close()}
   let output=try FileHandle(forWritingTo:staging);defer{try? output.close()}
   try output.seekToEnd();var remaining=Int(bytes)
   while remaining>0{guard let chunk=try input.read(upToCount:min(remaining,1024*1024)),!chunk.isEmpty else{throw AppError("原始音频不完整")};try output.write(contentsOf:chunk);remaining-=chunk.count}
   try output.synchronize();try output.close();try fm.moveItem(at:staging,to:recoveredURL)
  }
  return Recording(path:recoveredURL.path,offset:offset,duration:duration)
 }
}

struct SummaryCache:Codable {let key:String;let fields:[String:String]}
struct TextRevision:Codable,Identifiable {var id=UUID().uuidString;var date=Date();let reason:String;let meeting:Meeting}

enum MeetingDisk {
 static func save(_ meeting:Meeting,root:URL) throws {
  let folder=root.appendingPathComponent(meeting.id,isDirectory:true)
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:folder.path)
  let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
  try encoder.encode(meeting).write(to:folder.appendingPathComponent("meeting.json"),options:.atomic)
 }
}

// 五个页面共享可校验的内容节点；文字快照仍可读取旧版本存档。
struct AnalysisNode:Codable,Identifiable,Equatable {
 var title:String
 var body:String
 var speaker:String? = nil
 var times:[Double]
 var kind:String? = nil
 var owner:String? = nil
 var deadline:String? = nil
 var children:[AnalysisNode]? = nil
 var id:String { title+"|"+times.map{String($0)}.joined(separator:",") }
 static func decode(_ text:String)->[Self]? {try? JSONDecoder().decode([Self].self,from:Data(text.utf8))}
 static func encode(_ nodes:[Self])->String {String(decoding:(try? JSONEncoder().encode(nodes)) ?? Data(),as:UTF8.self)}
 static func plain(_ text:String)->String {
  guard let nodes=decode(text) else{return text}
  func lines(_ nodes:[Self],_ level:Int)->String {nodes.map{n in
   let heading=String(repeating:"  ",count:level)+(level==0 ? "## ":"• ")+n.title
   let label=[n.kind,n.speaker,n.owner.map{"负责人："+$0},n.deadline.map{"期限："+$0}].compactMap{$0}.filter{!$0.isEmpty}.joined(separator:" · ")
   let refs=n.times.map{"["+Wire.time($0)+"]"}.joined(separator:" ")
   return heading+"\n"+label+(label.isEmpty ? "":"\n")+n.body+" "+refs+(n.children?.isEmpty==false ? "\n"+lines(n.children!,level+1):"")
  }.joined(separator:"\n\n")};return lines(nodes,0)
 }
}
