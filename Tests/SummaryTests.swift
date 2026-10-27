import Foundation
@main struct Checks {
 static func main() throws {
  var m=Meeting();m.title="旧会议";m.sentences=[Sentence(start:1,end:3,text:"原文",speaker:"发言人1")];m.tree="旧观点记录"
  let original=try Wire.json(["id":m.id,"title":m.title,"created":0,"sentences":[],"recordings":[],"notes":"原笔记","summary":"原纪要","chapters":"原章节","tree":"旧观点记录","todos":"原待办"])
  let old=try JSONDecoder().decode(Meeting.self,from:original)
  precondition(old.disagreements==nil && old.notes=="原笔记" && old.tree=="旧观点记录")
  var next=old;next.disagreements="未发现明确分歧";let roundtrip=try JSONDecoder().decode(Meeting.self,from:JSONEncoder().encode(next));precondition(roundtrip.disagreements==next.disagreements)
  let fields=["summary":"结论[00:01]","tree":"议题→观点→结论[00:01]","disagreements":"未发现明确分歧。执行条件尚待验证。[00:01]","chapters":"开场[00:01]","todos":"任务，期限未明确。[00:01]"]
  let data=try Wire.json(fields);let result=try SummaryBundle.parse(String(data:data,encoding:.utf8)!);precondition(result.disagreements.contains("执行条件"))
  let fenced="```json\n"+String(data:data,encoding:.utf8)!+"\n```";let parsedFence=try SummaryBundle.parse(fenced);precondition(parsedFence==result)
  var broken=fields;broken.removeValue(forKey:"disagreements")
  do{_=try SummaryBundle.parse(String(data:Wire.json(broken),encoding:.utf8)!);preconditionFailure("缺少新字段不应覆盖旧纪要")}catch{}
  let references=SourceReference.extract("[10:55] [01:02:03] [10:55] [01:99] 与会人员[00:01]")
  precondition(references.map{$0.seconds}==[655,3723,1])
  precondition(ConnectionDiagnostics.safeCode("InvalidApiKey")=="InvalidApiKey")
  precondition(ConnectionDiagnostics.safeCode("Bearer secret-value") == nil)
  precondition(ConnectionDiagnostics.describe(URLError(.cannotFindHost),stage:"连接").contains("域名"))
  precondition(ConnectionDiagnostics.describe(URLError(.badServerResponse),stage:"连接",httpStatus:401).contains("Workspace"))
  precondition(!ConnectionDiagnostics.server(["error_message":"secret-value","error_code":"InvalidApiKey"]).contains("secret-value"))
  print("通过：旧会议兼容、新分歧字段存档、五字段AI结果及围栏解析、缺失字段保护、原文时间定位、连接错误分类和敏感错误内容隔离。")
 }
}
