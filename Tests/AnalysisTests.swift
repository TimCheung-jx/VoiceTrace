import Foundation
@main struct AnalysisChecks {
 static func main() async throws {
  let transcript="[00:00] 甲：我建议先试点。\n[00:12] 乙：我反对直接上线，先验证。\n[00:25] 甲：同意。乙周五提交验证结果。\n[00:40] 待区分发言人：指标下次确认。"
  let point=AnalysisNode(title:"先验证",body:"反对直接上线。",speaker:"乙",times:[12],children:[AnalysisNode(title:"回应",body:"同意先验证。",speaker:"甲",times:[25])])
  let topic=AnalysisNode(title:"上线安排",body:"验证后再定。",times:[0],children:[point])
  var dispute=topic;dispute.kind="明确意见冲突";dispute.children?.append(AnalysisNode(title:"先试点",body:"建议先试点。",speaker:"甲",times:[0]))
  var task=AnalysisNode(title:"提交验证结果",body:"提交接口验证结果。",times:[25],kind:"明确任务",owner:"乙",deadline:"周五")
  func raw(_ task:AnalysisNode)->String {String(decoding:try! Wire.json(["summary":try! JSONSerialization.jsonObject(with:JSONEncoder().encode([topic])),"tree":try! JSONSerialization.jsonObject(with:JSONEncoder().encode([topic])),"disagreements":try! JSONSerialization.jsonObject(with:JSONEncoder().encode([dispute])),"chapters":try! JSONSerialization.jsonObject(with:JSONEncoder().encode([topic])),"todos":try! JSONSerialization.jsonObject(with:JSONEncoder().encode([task]))]),as:UTF8.self)}
  let bundle=try SummaryBundle.validated(raw(task),transcript:transcript)
  precondition(bundle.structured && AnalysisNode.decode(bundle.todos)?.count==1)
  let plain=AnalysisNode.plain(bundle.tree);precondition(plain.contains("乙") && plain.contains("[00:12]") && !plain.contains("\"children\""))
  task.speaker="虚构姓名";do{_=try SummaryBundle.validated(raw(task),transcript:transcript);preconditionFailure("不得编造身份")}catch{}
  task.speaker=nil;task.times=[999];do{_=try SummaryBundle.validated(raw(task),transcript:transcript);preconditionFailure("不得虚构时间")}catch{}
  task.times=[25];task.deadline="明年六月";do{_=try SummaryBundle.validated(raw(task),transcript:transcript);preconditionFailure("不得虚构期限")}catch{}
  task.deadline="周五";task.owner="不存在的人";do{_=try SummaryBundle.validated(raw(task),transcript:transcript);preconditionFailure("不得虚构负责人")}catch{}
  do{_=try SummaryBundle.validated("{\"summary\":\"长段落\",\"tree\":\"无图\",\"disagreements\":\"无\",\"chapters\":\"无\",\"todos\":\"无\"}",transcript:transcript);preconditionFailure("新结果必须是结构化条目")}catch{}
  let longLine="[00:12] 乙："+String(repeating:"虚构长发言",count:1000)
  let pieces=SummaryPipeline.chunks(longLine,limit:1000)
  precondition(pieces.allSatisfy{$0.count<=1000 && $0.hasPrefix("[00:12] 乙：")})
  let round=try SummaryBundle.from(bundle.fields);precondition(round==bundle)
  let run=try await SummaryPipeline.run(text:String(repeating:transcript+"\n",count:200),scope:"fictional",cache:[],final:true,call:{_,_ in bundle},progress:{_,_ in})
  precondition(AnalysisNode.decode(run.bundle.todos)?.count==1 && AnalysisNode.decode(run.bundle.tree)?.count==1)
  var m=Meeting();m.todos=bundle.todos;m.completedTasks=[AnalysisNode.decode(bundle.todos)![0].id]
  let saved=try JSONDecoder().decode(Meeting.self,from:JSONEncoder().encode(m));precondition(saved.completedTasks==m.completedTasks)
  print("通过：结构化页面、观点分支、发言人及出处校验、伪造身份/时间/负责人拒绝、旧段落拒绝覆盖、长会议条目保留及完成状态存档。仅虚构资料。")
 }
}
