import Foundation
struct SummaryBundle:Equatable {
 let summary:String
 let tree:String
 let disagreements:String
 let chapters:String
 let todos:String
 static let prompt="""
请仅根据会议逐字稿整理，返回纯JSON对象，五个字段的值均为字符串：
summary：会议纪要，区分背景、讨论、会议决定、待确认。
tree：思维链，以“议题→与会人员观点→原文明确的理由→回应→会议结论”组织。这里的思维链指会议讨论脉络，不是模型的内部推理；不要补写原文没有的推理或动机。
disagreements：分歧点。对每个议题列出分类（明确意见冲突/执行条件不同/信息待确认）、各方姓名或现有发言人标签、各方主张及理由、冲突焦点、是否形成共识、当前处理安排和待确认事项。没有明确对立表述时，先写“未发现明确分歧”，再单独列出执行条件或待确认信息，不要制造人员冲突或推测态度。
chapters：按时间组织的章节与简短摘要。
todos：任务、负责人、期限；原文未明确的写“未明确”。
每条关键内容引用逐字稿已有的[分:秒]时间，禁止虚构出处、决定和期限。不输出代码围栏。
"""
 static func parse(_ raw:String) throws -> Self {
  var clean=raw.trimmingCharacters(in:.whitespacesAndNewlines)
  if clean.hasPrefix("```") && clean.hasSuffix("```") {
   guard let line=clean.firstIndex(of:"\n") else{throw AppError("整理结果格式不完整，旧纪要已保留")}
   clean=String(clean[clean.index(after:line)...].dropLast(3)).trimmingCharacters(in:.whitespacesAndNewlines)
  }
  let obj=try Wire.object(Data(clean.utf8))
  func field(_ key:String) throws -> String {
   guard let s=obj[key] as? String,!s.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{throw AppError("整理结果缺少\(key)字段；旧纪要已保留，请重试或更换模型")};return s
  }
  return try Self(summary:field("summary"),tree:field("tree"),disagreements:field("disagreements"),chapters:field("chapters"),todos:field("todos"))
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
   while remaining.count>limit{
    if !current.isEmpty{parts.append(current);current=""}
    let cut=remaining.index(remaining.startIndex,offsetBy:limit);parts.append(String(remaining[..<cut]));remaining=String(remaining[cut...])
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
   let key=digest("v2|"+scope+"|"+kind+"|"+source)
   if !(final && kind=="最终核对"),let fields=lookup[key]{let value=try SummaryBundle.from(fields);if value.fields.values.reduce(0,{$0+$1.count})<=resultLimit{used.append(SummaryCache(key:key,fields:fields));return value}}
   let instruction=SummaryBundle.prompt+"\n本次输入为"+(kind=="原文" ? "有时间标记的逐字稿片段":"已按原文整理的分段摘要，请去重归并，保留已有出处，不新增事实")+"。五个字段各尽量控制在600字以内，总计不得超过4000字符。保留决定、分歧、待办与关键时间。"+(final ? "用于最终整理，但原文未形成结论的事项仍写待确认。":"会议仍在进行，结果为草稿。")
   var value=try await call(source,instruction)
   if value.fields.values.reduce(0,{$0+$1.count})>resultLimit{value=try await call(source,instruction+"\n上次输出过长，本次必须精简到总计4000字符以内。")}
   guard value.fields.values.reduce(0,{$0+$1.count})<=resultLimit else{throw AppError("模型输出过长，已保留已有整理；请重试或更换模型")}
   try Task.checkCancellation()
   lookup[key]=value.fields;used.append(SummaryCache(key:key,fields:value.fields))
   progress(Array(lookup.map{SummaryCache(key:$0.key,fields:$0.value)}).suffix(512).map{$0},kind)
   return value
  }
  var layer:[SummaryBundle]=[]
  for (i,piece) in pieces.enumerated(){progress(Array(lookup.map{SummaryCache(key:$0.key,fields:$0.value)}),"原文分段 \(i+1)/\(pieces.count)");layer.append(try await resolve(piece,kind:"原文"))}
  let parts=layer
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
