import Foundation
struct SummaryBundle:Equatable {
 let summary:String
 let tree:String
 let disagreements:String
 let chapters:String
 let todos:String
 static let prompt="""
仅根据逐字稿返回纯JSON，五个字段summary、tree、disagreements、chapters、todos均为节点数组，不能是文字段落。
节点格式：{"title":"简短标题","body":"简洁说明","speaker":null,"times":[0],"kind":null,"owner":null,"deadline":null,"children":[]}。
所有字段都必须存在，未知值用null；times引用原文已有的时间，单位秒。禁止编造姓名、角色、决定、原因、责任人、截止日期。speaker必须逐字沿用原文标签，原文未区分则写“待区分发言人”，不能用“另一人”假装已识别身份。
summary：按背景、议题讨论、明确决定、待确认分组，每组children为独立条目；讨论条目必须列明原文speaker和出处。
tree：每个根节点是议题，其children是各发言人的观点节点（speaker必填），观点children分别是理由、回应、结论。仅呈现会议讨论关系，不是模型内部推理。结论未明确时如实标注；不得将多人意见挤在同一body。
disagreements：每个根节点是一个问题，kind只能为“明确意见冲突”“执行条件不同”“信息待确认”；children分别列各方立场，speaker必填，body写主张及理由。根body说明焦点、是否共识、处理安排。仅明确反对才属于意见冲突；没有冲突可返回空数组，不要制造对立。
chapters：按时间顺序逐项返回，title为章节名，body为该章摘要，times第一个数为开始秒数。
todos：每项单独任务，kind为“明确任务”或“建议跟进”；title为具体行动，body写交付物或待确认内容，owner、deadline只能沿用原文，未指定用null。不要把讨论方向写成已分配任务，没有任务可返回空数组。
summary、tree、chapters不能为空。每项内容必须有times出处，空数组代表确实未发现该类条目。不输出代码围栏。
"""
 static func parse(_ raw:String) throws -> Self {
  var clean=raw.trimmingCharacters(in:.whitespacesAndNewlines)
  if clean.hasPrefix("```") && clean.hasSuffix("```") {
   guard let line=clean.firstIndex(of:"\n") else{throw AppError("整理结果格式不完整，旧纪要已保留")}
   clean=String(clean[clean.index(after:line)...].dropLast(3)).trimmingCharacters(in:.whitespacesAndNewlines)
  }
  let obj=try Wire.object(Data(clean.utf8))
  func field(_ key:String) throws -> String {
   if let array=obj[key] as? [[String:Any]] {let data=try Wire.json(array);guard let nodes=AnalysisNode.decode(String(decoding:data,as:UTF8.self)) else{throw AppError("整理节点格式错误")};return AnalysisNode.encode(nodes)}
   guard let s=obj[key] as? String,!s.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{throw AppError("整理结果缺少\(key)字段；旧纪要已保留，请重试或更换模型")};return s
  }
  return try Self(summary:field("summary"),tree:field("tree"),disagreements:field("disagreements"),chapters:field("chapters"),todos:field("todos"))
 }
 var structured:Bool {fields.values.allSatisfy{AnalysisNode.decode($0) != nil}}
 static func validated(_ raw:String,transcript:String)throws->Self {
  let bundle=try parse(raw)
  guard bundle.structured else{throw AppError("模型未返回结构化条目；旧结果已保留，请重新整理")}
  let lines=transcript.components(separatedBy:"\n")
  let allowed=Set(SourceReference.extract(transcript).map{$0.seconds})
  var count=0
  func check(_ nodes:[AnalysisNode],depth:Int)throws {
   guard depth<=5 else{throw AppError("整理层级过深")}
   for n in nodes {
    count+=1
    guard count<=600,!n.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,!n.body.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,n.body.count<=1200,!n.times.isEmpty,n.times.allSatisfy({$0.isFinite && allowed.contains($0)}) else{throw AppError("整理条目缺少标题、内容或有效原文出处")}
    if let speaker=n.speaker,speaker != "待区分发言人" {
     guard n.times.contains(where:{t in lines.contains(where:{$0.hasPrefix("["+Wire.time(t)+"] "+speaker+"：")})}) else{throw AppError("整理中的发言人与原文不符")}
    }
    if let owner=n.owner,!lines.contains(where:{line in n.times.contains(where:{line.hasPrefix("["+Wire.time($0)+"] ")}) && line.contains(owner)}){throw AppError("整理中的负责人没有原文依据")}
    if let deadline=n.deadline,!lines.contains(where:{line in n.times.contains(where:{line.hasPrefix("["+Wire.time($0)+"] ")}) && line.contains(deadline)}){throw AppError("整理中的期限没有原文依据")}
    try check(n.children ?? [],depth:depth+1)
   }
  }
  for (key,value) in bundle.fields {
   let nodes=AnalysisNode.decode(value)!
   if ["summary","tree","chapters"].contains(key) && nodes.isEmpty{throw AppError("整理缺少必要内容")}
   if key=="tree" {guard nodes.allSatisfy({!($0.children ?? []).isEmpty && ($0.children ?? []).allSatisfy{$0.speaker?.isEmpty==false}}) else{throw AppError("思维链缺少观点或发言人")}}
   if key=="disagreements" {guard nodes.allSatisfy({["明确意见冲突","执行条件不同","信息待确认"].contains($0.kind ?? "") && ($0.children ?? []).allSatisfy{$0.speaker?.isEmpty==false} && ($0.kind != "明确意见冲突" || ($0.children ?? []).count>=2)}) else{throw AppError("分歧分类无效")}}
   if key=="todos" {guard nodes.allSatisfy({["明确任务","建议跟进"].contains($0.kind ?? "")}) else{throw AppError("待办分类无效")}}
   try check(nodes,depth:0)
  }
  return bundle
 }

}
struct SourceReference:Identifiable,Equatable {
 let label:String
 let seconds:Double
 var id:String {label}
 static func extract(_ text:String)->[Self] {
  let regex=try! NSRegularExpression(pattern:"\\[(\\d{1,3}):(\\d{2})(?::(\\d{2}))?\\]")
  let ns=text as NSString
  var seen=Set<String>()
  return regex.matches(in:text,range:NSRange(location:0,length:ns.length)).compactMap {m in
   let label=ns.substring(with:m.range).trimmingCharacters(in:CharacterSet(charactersIn:"[]"))
   guard seen.insert(label).inserted else{return nil}
   let a=Double(ns.substring(with:m.range(at:1))) ?? 0,b=Double(ns.substring(with:m.range(at:2))) ?? 0
   guard b<60 else{return nil}
   if m.range(at:3).location != NSNotFound {let c=Double(ns.substring(with:m.range(at:3))) ?? 0;guard c<60 else{return nil};return Self(label:label,seconds:a*3600+b*60+c)}
   return Self(label:label,seconds:a*60+b)
  }
 }
}
enum ConnectionDiagnostics {
 static func safeCode(_ raw:String?)->String? {guard let raw=raw,raw.range(of:"^[A-Za-z0-9_.:-]{1,96}$",options:.regularExpression) != nil else{return nil};return raw}
 static func describe(_ error:Error,stage:String,httpStatus:Int?=nil)->String {
  var message="失败阶段：\(stage)。"
  if let status=httpStatus {
   message+="HTTP \(status)。"
   if status==401 || status==403 {return message+"请核对该地域的API Key、Workspace ID及模型权限。"}
   if status==404 {return message+"请核对Workspace ID、地域与模型名称。"}
   if status==429 {return message+"调用受限，请检查额度、并发限制并稍后重试。"}
  }
  if let app=error as? AppError{return message+app.message}
  let code=(error as NSError).code
  if let url=error as? URLError {
   switch url.code {
   case .cannotConnectToHost:return message+"无法连接百炼服务器（-1004）。请检查网络、代理及地域连接地址；尚不能据此判断密钥错误。"
   case .cannotFindHost,.dnsLookupFailed:return message+"无法解析服务域名，请核对Workspace ID、地域及网络DNS。"
   case .notConnectedToInternet,.networkConnectionLost:return message+"网络未连接或连接已中断。"
   case .timedOut:return message+"连接超时，请检查网络或代理设置。"
   case .secureConnectionFailed,.serverCertificateUntrusted:return message+"安全连接未能建立，请检查系统时间及网络代理。"
   default:break
   }
  }
  return message+"系统错误码 \(code)。请核对网络、接口配置或麦克风输入设备。"
 }
 static func server(_ header:[String:Any])->String {
  let code=safeCode(header["error_code"] as? String) ?? "未提供安全可显示的错误码"
  return "百炼任务失败（\(code)）。请核对地域、模型权限、余额及请求配置。"
 }
}

// 定长原文块+有界分层归并。未变化的块和归并节点按内容指纹复用。
import CryptoKit
extension SummaryBundle {
 var fields:[String:String]{["summary":summary,"tree":tree,"disagreements":disagreements,"chapters":chapters,"todos":todos]}
 static func from(_ fields:[String:String]) throws -> Self {try parse(String(decoding:Wire.json(fields),as:UTF8.self))}
}
struct SummaryRun {let bundle:SummaryBundle;let cache:[SummaryCache];let parts:[SummaryBundle]}
enum SummaryPipeline {
 static let sourceLimit=10000
 static let resultLimit=4000
 static func chunks(_ text:String,limit:Int=sourceLimit)->[String]{
  guard limit>0 else{return []};var parts:[String]=[];var current=""
  for line in text.components(separatedBy:"\n"){
   var remaining=line
   let range=line.range(of:"^\\[[^\\]]+\\] [^：]+：",options:.regularExpression)
   let header=range.map{String(line[$0])} ?? ""
   let continuation=header.count<limit/2 ? header:""
   while remaining.count>limit{
    if !current.isEmpty{parts.append(current);current=""}
    let cut=remaining.index(remaining.startIndex,offsetBy:limit);parts.append(String(remaining[..<cut]));remaining=continuation+String(remaining[cut...])
   }
   if current.count+remaining.count+1>limit{parts.append(current);current=""}
   if !remaining.isEmpty{current += (current.isEmpty ? "":"\n")+remaining}
  }
  if !current.isEmpty{parts.append(current)};return parts
 }
 static func digest(_ text:String)->String{SHA256.hash(data:Data(text.utf8)).map{String(format:"%02x",$0)}.joined()}
 static func run(text:String,scope:String,cache:[SummaryCache],final:Bool,
  call:(String,String) async throws -> SummaryBundle,
  progress:([SummaryCache],String)->Void) async throws -> SummaryRun {
  let pieces=chunks(text);guard !pieces.isEmpty else{throw AppError("暂无可整理的逐字稿")}
  var lookup=Dictionary(cache.map{($0.key,$0.fields)},uniquingKeysWith:{$1})
  var used:[SummaryCache]=[]
  func resolve(_ source:String,kind:String) async throws -> SummaryBundle {
   try Task.checkCancellation()
   let key=digest("v3|"+(final ? "final|":"draft|")+scope+"|"+kind+"|"+source)
   if !(final && kind=="最终核对"),let fields=lookup[key]{let value=try SummaryBundle.from(fields);if value.fields.values.reduce(0,{$0+$1.count})<=(value.structured ? 48000:resultLimit){used.append(SummaryCache(key:key,fields:fields));return value}}
   let instruction=SummaryBundle.prompt+"\n本次输入为"+(kind=="原文" ? "有时间标记的逐字稿片段":"已按原文整理的分段摘要，请去重归并，保留已有出处，不新增事实")+"。保留每项任务、各方观点和出处；每个节点正文不超过200字，按节点拆分，禁止输出大段文字。"+(final ? "用于最终整理，但原文未形成结论的事项仍写待确认。":"会议仍在进行，结果为草稿。")
   var value=try await call(source,instruction)
   if value.fields.values.reduce(0,{$0+$1.count})>(value.structured ? 48000:resultLimit){value=try await call(source,instruction+"\n上次输出过长，本次必须精简到总计4000字符以内。")}
   guard value.fields.values.reduce(0,{$0+$1.count})<=(value.structured ? 48000:resultLimit) else{throw AppError("模型输出过长，已保留已有整理；请重试或更换模型")}
   try Task.checkCancellation()
   lookup[key]=value.fields;used.append(SummaryCache(key:key,fields:value.fields))
   progress(Array(lookup.map{SummaryCache(key:$0.key,fields:$0.value)}).suffix(512).map{$0},kind)
   return value
  }
  var layer:[SummaryBundle]=[]
  for (i,piece) in pieces.enumerated(){progress(Array(lookup.map{SummaryCache(key:$0.key,fields:$0.value)}),"原文分段 \(i+1)/\(pieces.count)");layer.append(try await resolve(piece,kind:"原文"))}
  let parts=layer
  if layer.allSatisfy({$0.structured}) {
   var merged:[String:String]=[:]
   for key in ["summary","tree","disagreements","chapters","todos"] {
    var nodes:[AnalysisNode]=[]
    for bundle in layer {for node in AnalysisNode.decode(bundle.fields[key]!)! {if !nodes.contains(where:{$0==node}){nodes.append(node)}}}
    if key=="chapters"{nodes.sort{($0.times.first ?? 0)<($1.times.first ?? 0)}}
    merged[key]=AnalysisNode.encode(nodes)
   }
   return SummaryRun(bundle:try SummaryBundle.from(merged),cache:used,parts:parts)
  }
  while layer.count>1{
   var next:[SummaryBundle]=[]
   // 两个至多4000字符的摘要，加JSON字段后仍为有界输入。
   for index in stride(from:0,to:layer.count,by:2){
    if index+1==layer.count{next.append(layer[index]);continue}
    let source=String(decoding:try Wire.json(["前段":layer[index].fields,"后段":layer[index+1].fields]),as:UTF8.self)
    next.append(try await resolve(source,kind:"归并"))
   };layer=next
  }
  let result:SummaryBundle
  if final{let source=String(decoding:try Wire.json(layer[0].fields),as:UTF8.self);result=try await resolve(source,kind:"最终核对")}else{result=layer[0]}
  return SummaryRun(bundle:result,cache:used,parts:parts)
 }
}

struct QuestionContext {
 let text:String
 let partial:Bool
 static func select(transcript:String,question:String,overview:String)->Self{
  guard transcript.count>30000 else{return Self(text:transcript,partial:false)}
  let query=Array(question.lowercased().filter{!$0.isWhitespace && !$0.isPunctuation})
  var terms=Set<String>();if query.count>1{for i in 0..<(query.count-1){terms.insert(String(query[i...i+1]))}}
  let chunks=SummaryPipeline.chunks(transcript)
  var scored:[(Int,Int)]=[]
  for (index,text) in chunks.enumerated(){let lower=text.lowercased();var score=0;for term in terms{if lower.contains(term){score+=1}};scored.append((index,score))}
  scored.sort{left,right in if left.1==right.1{return left.0<right.0};return left.1>right.1}
  let selected=scored.prefix(3).map{$0.0}.sorted().map{chunks[$0]}.joined(separator:"\n\n")
  return Self(text:"会议总览（可能包含人工修订）：\n"+String(overview.prefix(6000))+"\n\n检索的原文片段：\n"+selected,partial:true)
 }
}
