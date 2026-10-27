import Foundation
@main struct Checks {
 static func main() throws {
  let id=UUID().uuidString
  let run=Wire.command("run-task",id:id)
  let h=run["header"] as! [String:String];let p=run["payload"] as! [String:Any]
  precondition(h["task_id"]==id && h["streaming"]=="duplex")
  precondition(p["model"] as? String == "fun-asr-realtime")
  let params=p["parameters"] as! [String:Any];precondition(params["format"] as? String == "pcm" && params["sample_rate"] as? Int == 16000)
  let stop=Wire.command("finish-task",id:id);precondition((stop["header"] as! [String:String])["task_id"]==id)
  precondition(Wire.sentence(["heartbeat":true,"text":""],offset:0)==nil)
  let s=Wire.sentence(["begin_time":1000,"end_time":2800,"text":"测试","speaker_id":1],offset:10)!
  precondition(s.start==11 && s.end==12.8 && s.speaker=="本段发言人2")
  precondition(Wire.sentence(["text":"中间结果"],offset:0)!.speaker=="待区分发言人")
  precondition(Wire.wavHeader(bytes:32000).count==44)
  let header=Wire.wavHeader(bytes:32000);precondition(String(data:header.prefix(4),encoding:.ascii)=="RIFF");precondition(header[22]==1 && header[34]==16)
  precondition(Wire.time(655)=="10:55")
  precondition(Wire.validateWorkspace("llm-test-123") && !Wire.validateWorkspace("test/path") && !Wire.validateWorkspace(""))
  let original=Meeting(sentences:[s]);let restored=try JSONDecoder().decode(Meeting.self,from:JSONEncoder().encode(original));precondition(restored.sentences.first?.text=="测试")
  _=try Wire.object(Wire.json(run))
  print("通过：实时任务协议、结束任务关联、心跳过滤、时间偏移、发言人标签、WAV头、配置校验及会议存档往返。")
 }
}
