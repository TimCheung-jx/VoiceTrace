import Foundation
final class StubProtocol:URLProtocol {
 static var handler:((URLRequest)throws->(Int,Data))?
 override class func canInit(with request:URLRequest)->Bool{true}
 override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
 override func startLoading(){do{let (status,data)=try Self.handler!(request);client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)}catch{client?.urlProtocol(self,didFailWithError:error)}}
 override func stopLoading(){}
}
@main struct Tests {
 static func main() async throws {
  let defaults=UserDefaults(suiteName:"voicetrace.tests."+UUID().uuidString)!
  defaults.set("ws-test",forKey:"workspace");defaults.set("fun-asr-realtime-2026-02-28",forKey:"realtimeModel")
  var settings=SettingsFile.load(defaults)
  precondition(settings.activeSpeech.workspace.isEmpty && settings.activeSpeech.realtimeModel=="fun-asr-realtime")
  precondition(settings.activeSpeech.keyAccount.hasPrefix("speech.") && settings.activeText.keyAccount.hasPrefix("text."))
  let legacy=settings.activeSpeech;var updated=legacy;updated.workspace="other-workspace";precondition(updated.keyAccount != legacy.keyAccount)
  updated=legacy;updated.region="ap-southeast-1";precondition(updated.keyAccount != legacy.keyAccount)
  var text=settings.activeText;text.provider="compatible";text.baseURL="https://example.invalid/v1/";text=try text.validated();precondition(text.baseURL=="https://example.invalid/v1" && text.keyAccount != "deepseek")
  for url in ["http://example.invalid","https://user:password@example.invalid","https://example.invalid?key=value","https://example.invalid/chat/completions"] {var bad=text;bad.baseURL=url;do{_=try bad.validated();preconditionFailure("应拒绝不合规地址")}catch{}}
  var second=SpeechProfile();second.workspace="second";second.name="备用语音";second.fileModel="paraformer-v2";_=try second.validated()
  settings.upsert(second);settings.upsert(text);try settings.save(defaults)
  let restored=SettingsFile.load(defaults);precondition(restored==settings && restored.speech.count==2 && restored.texts.count==1)
  let snapshot=ServiceConfig(speech:restored.activeSpeech,text:restored.activeText)
  var later=restored.activeSpeech;later.realtimeModel="fun-asr-realtime-2026-02-28";settings.upsert(later)
  precondition(snapshot.realtimeModel=="fun-asr-realtime" && settings.activeSpeech.realtimeModel != snapshot.realtimeModel)
  _=try snapshot.request(text.chatURL,key:"synthetic-test-value")
  do{_=try snapshot.request("https://unconfigured.invalid/chat/completions",key:"synthetic-test-value");preconditionFailure("应拒绝未配置地址")}catch{}
  let conf=URLSessionConfiguration.ephemeral;conf.protocolClasses=[StubProtocol.self];Network.shared.session=URLSession(configuration:conf)
  StubProtocol.handler={request in
   precondition(request.url!.absoluteString==text.chatURL)
   let bodyData:Data
   if let data=request.httpBody{bodyData=data}else{let stream=request.httpBodyStream!;stream.open();defer{stream.close()};var bytes=Data();var buffer=[UInt8](repeating:0,count:4096);while true{let n=stream.read(&buffer,maxLength:buffer.count);if n<=0{break};bytes.append(contentsOf:buffer.prefix(n))};bodyData=bytes}
   let obj=try Wire.object(bodyData);precondition(obj["model"] as? String==text.model)
   return (200,try Wire.json(["choices":[["message":["content":"连接成功"]]]]))
  }
  let result=try await Cloud(config:snapshot).testText(key:"synthetic-test-value");precondition(result.contains("成功"))
  StubProtocol.handler={_ in (401,Data("不要显示服务端敏感内容".utf8))}
  do{_=try await Cloud(config:snapshot).testText(key:"synthetic-test-value");preconditionFailure("应报告鉴权失败")}catch{precondition(error.localizedDescription.contains("401") && !error.localizedDescription.contains("敏感内容"))}
  print("通过：清洁配置初始化、多套存档、独立密钥范围、地址校验、任务快照、兼容接口模型路由、连接测试及鉴权错误保护。未读取真实密钥、未联网。")
 }
}
