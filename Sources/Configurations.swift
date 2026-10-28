import Foundation
import CryptoKit
enum AppIdentity {
 #if PERSONAL_BUILD
 static let keychainService="com.tim.tingjian"
 static let dataDirectory="听见会议资料"
 static let personal=true
 #else
 static let keychainService="org.voicetrace.app"
 static let dataDirectory="VoiceTrace"
 static let personal=false
 #endif
}
struct SpeechProfile: Codable, Identifiable, Equatable {
 var id=UUID().uuidString
 var name="百炼语音配置"
 var region="cn-beijing"
 var workspace=""
 var realtimeModel="fun-asr-realtime"
 var fileModel="fun-asr"
 var legacyScope:String?=nil
 var scope:String {region+":"+workspace}
 var keyAccount:String {
  #if PERSONAL_BUILD
  if legacyScope==scope{return "aliyun"}
  #endif
  return "speech."+id+"."+SettingsFile.digest(scope)
 }
 var host:String {"\(workspace).\(region).maas.aliyuncs.com"}
 var uploadHost:String {region=="ap-southeast-1" ? "dashscope-intl.aliyuncs.com":"dashscope.aliyuncs.com"}
 func validated() throws -> Self {
  var value=self
  value.name=name.trimmingCharacters(in:.whitespacesAndNewlines)
  value.workspace=workspace.trimmingCharacters(in:.whitespacesAndNewlines)
  value.realtimeModel=realtimeModel.trimmingCharacters(in:.whitespacesAndNewlines)
  value.fileModel=fileModel.trimmingCharacters(in:.whitespacesAndNewlines)
  guard !value.name.isEmpty,Wire.validateWorkspace(value.workspace) else{throw AppError("请填写配置名称和有效的Workspace ID")}
  guard ["cn-beijing","ap-southeast-1"].contains(region) else{throw AppError("当前支持百炼北京和新加坡地域")}
  guard value.realtimeModel=="fun-asr-realtime" || value.realtimeModel.hasPrefix("fun-asr-realtime-") else{throw AppError("实时识别目前支持Fun-ASR-Realtime协议，请填写fun-asr-realtime或其对应版本名")}
  guard ["fun-asr","paraformer-v2","qwen-audio-3.0-asr-flash-filetrans"].contains(value.fileModel) else{throw AppError("请选择当前已适配的会后识别模型")}
  return value
 }
}
struct TextProfile: Codable, Identifiable, Equatable {
 var id=UUID().uuidString
 var name="DeepSeek"
 var provider="deepseek"
 var baseURL="https://api.deepseek.com"
 var model="deepseek-flash"
 var legacyScope:String?=nil
 var keyAccount:String {
  #if PERSONAL_BUILD
  if legacyScope==baseURL{return "deepseek"}
  #endif
  return "text."+id+"."+SettingsFile.digest(baseURL)
 }
 var chatURL:String {baseURL+"/chat/completions"}
 func validated() throws -> Self {
  var value=self;value.name=name.trimmingCharacters(in:.whitespacesAndNewlines);value.model=model.trimmingCharacters(in:.whitespacesAndNewlines)
  var base=baseURL.trimmingCharacters(in:.whitespacesAndNewlines);while base.hasSuffix("/"){base.removeLast()};value.baseURL=base
  guard !value.name.isEmpty,!value.model.isEmpty else{throw AppError("请填写配置名称与模型名")}
  guard ["deepseek","compatible"].contains(provider),let url=URL(string:base),url.scheme=="https",url.host != nil,url.user==nil,url.password==nil,url.query==nil,url.fragment==nil else{throw AppError("接口基础地址必须为有效HTTPS地址，不要包含密钥、查询参数或账号密码")}
  guard !base.hasSuffix("/chat/completions") else{throw AppError("请填写基础地址，例如https://api.deepseek.com；不要包含/chat/completions")}
  if provider=="deepseek",url.host != "api.deepseek.com" {throw AppError("DeepSeek官方配置应使用api.deepseek.com；其他服务请选择兼容接口")}
  return value
 }
}
struct SettingsFile: Codable, Equatable {
 var speech:[SpeechProfile]
 var texts:[TextProfile]
 var speechID:String
 var textID:String
 var activeSpeech:SpeechProfile {speech.first{$0.id==speechID} ?? speech[0]}
 var activeText:TextProfile {texts.first{$0.id==textID} ?? texts[0]}
 static func digest(_ s:String)->String {SHA256.hash(data:Data(s.utf8)).map{String(format:"%02x",$0)}.joined()}
 static func fresh()->Self {
  let s=SpeechProfile();let t=TextProfile()
  return Self(speech:[s],texts:[t],speechID:s.id,textID:t.id)
 }
 static func load(_ defaults:UserDefaults)->Self {
  if let data=defaults.data(forKey:"modelSettingsV1"),let saved=try? JSONDecoder().decode(Self.self,from:data),!saved.speech.isEmpty,!saved.texts.isEmpty{return saved}
  #if PERSONAL_BUILD
  if let workspace=defaults.string(forKey:"workspace"),Wire.validateWorkspace(workspace){
   var speech=SpeechProfile();speech.id="legacy-speech";speech.workspace=workspace;speech.realtimeModel=defaults.string(forKey:"realtimeModel") ?? speech.realtimeModel;speech.legacyScope=speech.scope
   var text=TextProfile();text.id="legacy-text";text.model=defaults.string(forKey:"deepModel") ?? text.model;text.legacyScope=text.baseURL
   return Self(speech:[speech],texts:[text],speechID:speech.id,textID:text.id)
  }
  #endif
  return fresh()
 }
 func save(_ defaults:UserDefaults) throws {defaults.set(try JSONEncoder().encode(self),forKey:"modelSettingsV1")}
 mutating func upsert(_ p:SpeechProfile){if let i=speech.firstIndex(where:{$0.id==p.id}){speech[i]=p}else{speech.append(p)};speechID=p.id}
 mutating func upsert(_ p:TextProfile){if let i=texts.firstIndex(where:{$0.id==p.id}){texts[i]=p}else{texts.append(p)};textID=p.id}
}
