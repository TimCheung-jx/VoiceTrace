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
