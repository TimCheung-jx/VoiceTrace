import SwiftUI
import AVFoundation
import AppKit
@MainActor final class Workspace: ObservableObject {
 @Published var meeting=Meeting()
 @Published var history:[Meeting]=[]
 @Published var phase="空闲"
 @Published var status="配置百炼后，点击开始录音"
 @Published var partial=""
 @Published var alert=""
 @Published var tab="转写"
 @Published var settings=false
 @Published var settingsPage="外观"
 @Published var highlightedSentence:String?=nil
 @Published var playbackPosition:Double=0
 @Published var playing=false
 @Published var question=""
 @Published var answer=""
 @Published var processing=false
 @Published var modelSettings=SettingsFile.load(.standard)
 @Published var theme=UserDefaults.standard.string(forKey:"nativeTheme") ?? "燕麦森林"
 let root:URL
 var folder:URL {root.appendingPathComponent(meeting.id,isDirectory:true)}
 var config:ServiceConfig {ServiceConfig(speech:modelSettings.activeSpeech,text:modelSettings.activeText)}
 var elapsed:Double {meeting.recordings.reduce(0){$0+$1.duration}+(capture?.duration() ?? 0)}
 var locked:Bool {phase != "空闲" || processing}
 private var capture:AudioCapture?
 private var socket:URLSessionWebSocketTask?
 private var receiver:Task<Void,Never>?
 private var sender:Task<Void,Never>?
 private var watchdog:Task<Void,Never>?
 private var continuation:AsyncStream<Data>.Continuation?
 private var taskID=""
 private var offset:Double=0
 private var scheduledPause=false
 private var finalIDs=Set<String>()
 private var player:AVAudioPlayer?
 private var playbackOffset:Double=0
 private var playbackTicker:Timer?
 init() {
  let docs=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
  root=ProcessInfo.processInfo.environment["VOICETRACE_DATA_DIR"].map { URL(fileURLWithPath:$0,isDirectory:true) } ?? docs.appendingPathComponent("VoiceTrace",isDirectory:true)
  do {try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:root.path)} catch {alert="无法创建资料目录，请检查文稿目录权限"}
  refresh()
 }
 func refresh() {
  guard let dirs=try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil) else{return}
  history=dirs.compactMap {try? JSONDecoder().decode(Meeting.self,from:Data(contentsOf:$0.appendingPathComponent("meeting.json")))}.sorted{$0.created>$1.created}
 }
 func persist() {
  guard meeting.title != "新会议" || !meeting.sentences.isEmpty || !meeting.recordings.isEmpty || !meeting.notes.isEmpty || !meeting.summary.isEmpty else{return}
  do {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:folder.path);let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];try encoder.encode(meeting).write(to:folder.appendingPathComponent("meeting.json"),options:.atomic);refresh()} catch {alert="本地保存失败，请检查磁盘空间和文稿目录权限。请立即导出已有文字。"}
 }
 func newMeeting() {guard !locked else{return};persist();stopPlay();playbackPosition=0;highlightedSentence=nil;meeting=Meeting();partial="";answer="";status="新会议 · 可以开始录音"}
 func load(_ item:Meeting) {guard !locked else{return};persist();stopPlay();playbackPosition=0;highlightedSentence=nil;meeting=item;partial="";answer="";status="已打开本地会议"}
 func saveSpeechProfile(_ draft:SpeechProfile,key:String) throws {
  guard !locked else{throw AppError("请等待当前录音或整理结束后再切换配置")}
  let profile=try draft.validated();try Vault.save(profile.keyAccount,key.trimmingCharacters(in:.whitespacesAndNewlines))
  var updated=modelSettings;updated.upsert(profile);try updated.save(.standard);modelSettings=updated;status="语音配置已切换，下一次录音或会后整理生效"
 }
 func saveTextProfile(_ draft:TextProfile,key:String) throws {
  guard !locked else{throw AppError("请等待当前录音或整理结束后再切换配置")}
  let profile=try draft.validated();try Vault.save(profile.keyAccount,key.trimmingCharacters(in:.whitespacesAndNewlines))
  var updated=modelSettings;updated.upsert(profile);try updated.save(.standard);modelSettings=updated;status="整理配置已切换，下一次生成或问答生效"
 }
 func report(_ error:Error){alert=(error as? AppError)?.message ?? ConnectionDiagnostics.describe(error,stage:"当前操作")}
 func start() async {
  guard !locked else{return};let selected=config
  do {_=try selected.speech.validated()}catch{report(error);settingsPage="模型与服务";settings=true;return}
  let key=Vault.read(selected.speech.keyAccount);guard !key.isEmpty else{settingsPage="模型与服务";settings=true;return};stopPlay()
  phase="连接中";status="正在申请麦克风权限…"
  let allowed=await AVCaptureDevice.requestAccess(for:.audio)
  guard allowed else{phase="空闲";alert="请在系统设置 → 隐私与安全性 → 麦克风中允许声迹使用麦克风";return}
  if meeting.title=="新会议"{let formatter=DateFormatter();formatter.dateFormat="yyyy-MM-dd HH:mm";meeting.title="会议 "+formatter.string(from:Date())}
  persist();offset=meeting.recordings.reduce(0){$0+$1.duration};taskID=UUID().uuidString;finalIDs=[];partial="";tab="转写";scheduledPause=false
  guard let url=URL(string:"wss://\(selected.host)/api-ws/v1/inference") else{phase="空闲";return}
  var req=URLRequest(url:url);req.setValue("Bearer \(key)",forHTTPHeaderField:"Authorization");req.setValue(selected.workspace,forHTTPHeaderField:"X-DashScope-WorkSpace")
  let ws=Network.shared.session.webSocketTask(with:req);socket=ws;ws.resume();status="正在连接百炼，尚未开始录音…"
  let expected=taskID
  var failureStage="连接百炼实时服务"
  watchdog=Task {try? await Task.sleep(nanoseconds:20_000_000_000);if !Task.isCancelled,self.taskID==expected,self.phase=="连接中"{self.fail("连接超时，请检查百炼地域、业务空间ID、密钥与模型权限")}}
  receiver=Task {
   do {
    try await ws.send(.string(String(data:try Wire.json(Wire.command("run-task",id:expected,model:selected.realtimeModel)),encoding:.utf8)!))
    while !Task.isCancelled {
     let message=try await ws.receive();let data:Data
     switch message {case .data(let d):data=d;case .string(let s):data=Data(s.utf8);@unknown default:continue}
     guard self.taskID==expected else{return}
     let object=try Wire.object(data);let header=object["header"] as? [String:Any] ?? [:]
     if let id=header["task_id"] as? String,id != expected {continue}
     switch header["event"] as? String {
     case "task-started": failureStage="启动麦克风";try self.beginCapture(ws:ws);failureStage="接收实时转写";self.watchdog?.cancel()
     case "result-generated":
      if let payload=object["payload"] as? [String:Any],let output=payload["output"] as? [String:Any],let sentence=output["sentence"] as? [String:Any],let row=Wire.sentence(sentence,offset:self.offset){
       if sentence["sentence_end"] as? Bool == true {let sid="\(sentence["sentence_id"] ?? "")-\(sentence["begin_time"] ?? 0)";if self.finalIDs.insert(sid).inserted{self.meeting.sentences.append(row);self.persist()};self.partial=""} else {self.partial=row.text}
      }
     case "task-finished":self.finishConnection();return
     case "task-failed":self.fail(ConnectionDiagnostics.server(header));return
     default:break
     }
    }
   } catch {if !Task.isCancelled && self.taskID==expected && self.phase != "空闲"{self.fail(ConnectionDiagnostics.describe(error,stage:failureStage,httpStatus:(ws.response as? HTTPURLResponse)?.statusCode))}}
  }
 }
 private func beginCapture(ws:URLSessionWebSocketTask) throws {
  guard phase=="连接中",capture==nil else{return}
  var pipe:AsyncStream<Data>.Continuation!
  let stream=AsyncStream<Data>(bufferingPolicy:.bufferingOldest(40)){pipe=$0};continuation=pipe
  let sink=pipe!;let expected=taskID
  sender=Task {
   do {for await data in stream {guard !Task.isCancelled else{return};try await ws.send(.data(data))};if self.taskID==expected && self.phase=="结束中" {try await ws.send(.string(String(data:try Wire.json(Wire.command("finish-task",id:expected)),encoding:.utf8)!))}}
   catch {if self.taskID==expected && self.phase != "空闲"{self.fail(ConnectionDiagnostics.describe(error,stage:"发送实时音频",httpStatus:(ws.response as? HTTPURLResponse)?.statusCode))}}
  }
  let audio=AudioCapture();capture=audio
  try audio.start(directory:folder,yield:{data in
   if case .dropped = sink.yield(data) {Task {@MainActor in if self.taskID==expected && self.phase != "空闲"{self.fail("网络发送速度不足，本段已停止并保存，未发送内容可会后补转写。")}}}
  },fail:{Task {@MainActor in if self.taskID==expected && self.phase != "空闲"{self.fail("音频转换或写盘失败，本段已停止。请检查输入设备及磁盘空间。")}}})
  phase="录音中";status="● 正在录音并实时转写 · 发言人待会后区分"
 }
 private func stopCapture() {
  guard let audio=capture else{return};capture=nil
  do {if let (url,duration)=try audio.stop(){meeting.recordings.append(Recording(path:url.path,offset:offset,duration:duration));persist()}} catch {report(error)}
 }
 func stop(pause:Bool=false) {
  guard phase=="录音中" else{return};scheduledPause=pause;phase="结束中";stopCapture();continuation?.finish();status="正在等待最后一句识别结果…"
  let expected=taskID;watchdog?.cancel();watchdog=Task {try? await Task.sleep(nanoseconds:20_000_000_000);if !Task.isCancelled,self.taskID==expected,self.phase=="结束中"{self.fail("等待最后结果超时。本地录音和已收到的文字已保存，可会后补转写。")}}
 }
 private func finishConnection() {
  stopCapture()
  watchdog?.cancel();socket?.cancel(with:.normalClosure,reason:nil);socket=nil;sender=nil;receiver=nil;continuation=nil;phase="空闲";partial="";persist();status=scheduledPause ? "已暂停 · 点击继续录音创建下一段" : "录音已保存 · 可整理发言人或生成纪要"
 }
 private func fail(_ message:String) {
  let hadCapture=capture != nil
  stopCapture();continuation?.finish();sender?.cancel();receiver?.cancel();watchdog?.cancel();socket?.cancel(with:.goingAway,reason:nil);socket=nil;continuation=nil;phase="空闲";status="操作已停止 · 请查看提示";alert=message+(hadCapture ? "\n已停止采集；请在会议资料目录核对本段录音。":"\n此次尚未开始采集录音。")
  if !partial.isEmpty {meeting.notes += "\n[未定稿，请回听核对] "+partial;partial=""};persist()
 }
 func addMark(){let t=elapsed;meeting.notes += "\n[\(Wire.time(t))] 重点：";tab="笔记";persist()}
 var totalDuration:Double {meeting.recordings.reduce(0){max($0,$1.offset+$1.duration)}}
 func play(_ time:Double) {
  guard phase=="空闲",let r=meeting.recordings.last(where:{$0.offset<=time}) else{status="暂无可回听的本地录音";return}
  do {player?.stop();player=try AVAudioPlayer(contentsOf:URL(fileURLWithPath:r.path));playbackOffset=r.offset;player?.currentTime=max(0,time-r.offset);playing=player?.play() ?? false;playbackPosition=time
   playbackTicker?.invalidate();playbackTicker=Timer.scheduledTimer(withTimeInterval:0.2,repeats:true){[weak self] _ in Task {@MainActor [weak self] in guard let self=self else{return};if let player=self.player {self.playbackPosition=self.playbackOffset+player.currentTime;if !player.isPlaying,player.currentTime>=player.duration-0.15,let next=self.meeting.recordings.first(where:{$0.offset>self.playbackOffset+0.01}){self.play(next.offset)}else{self.playing=player.isPlaying;if !player.isPlaying{self.playbackTicker?.invalidate()}}}}}
  } catch {alert="无法读取本地录音，请检查文件是否被移动"}
 }
 func togglePlayback(){if playing {player?.pause();playing=false;playbackTicker?.invalidate()}else{play(playbackPosition)}}
 func stopPlay(){player?.stop();playing=false;playbackTicker?.invalidate()}
 func seek(_ time:Double){playbackPosition=time;if playing{play(time)}}
 func revealSource(_ seconds:Double){tab="转写";highlightedSentence=meeting.sentences.min(by:{abs($0.start-seconds)<abs($1.start-seconds)})?.id;play(seconds)}
 func cancelConnecting(){guard phase=="连接中" else{return};fail("连接已取消。")}
 var transcript:String {meeting.sentences.map{"[\(Wire.time($0.start))] \($0.speaker)：\($0.text)"}.joined(separator:"\n")}
 func diarize() async {
  guard !locked,!meeting.recordings.isEmpty else{return};let selected=config;let key=Vault.read(selected.speech.keyAccount);guard !key.isEmpty else{settingsPage="模型与服务";settings=true;return}
  processing=true;defer{processing=false};var updated:[Sentence]=[]
  do {for (i,r) in meeting.recordings.enumerated(){status="正在整理第\(i+1)/\(meeting.recordings.count)段发言人…";var rows=try await Cloud(config:selected).diarize(r,key:key);for j in rows.indices{rows[j].speaker="第\(i+1)段·"+rows[j].speaker};updated+=rows}
   guard !updated.isEmpty else{throw AppError("服务未识别到语音，原逐字稿未更改")}
   let backup=folder.appendingPathComponent("实时原稿-\(UUID().uuidString).json");try JSONEncoder().encode(meeting.sentences).write(to:backup)
   meeting.sentences=updated;persist();status="发言人整理完成 · 跨录音段身份需人工核对"
  }catch{report(error);status="会后整理未完成 · 原逐字稿保持不变"}
 }
 func generate() async {
  guard !locked else{return};let selected=config;let key=Vault.read(selected.text.keyAccount);guard !key.isEmpty else{settingsPage="模型与服务";settings=true;return}
  processing=true;defer{processing=false};status="所选模型正在整理会议…"
  do {let text=try await Cloud(config:selected).chat(text:transcript,question:SummaryBundle.prompt,key:key)
   let bundle=try SummaryBundle.parse(text)
   if !meeting.summary.isEmpty {try JSONEncoder().encode(meeting).write(to:folder.appendingPathComponent("整理前备份-"+UUID().uuidString+".json"))}
   meeting.summary=bundle.summary;meeting.chapters=bundle.chapters;meeting.tree=bundle.tree;meeting.disagreements=bundle.disagreements;meeting.todos=bundle.todos;persist();tab="AI纪要";status="AI整理完成 · 请回听核对"
  } catch{report(error);status="AI整理未完成"}
 }
 func ask() async {
  guard !locked,!question.trimmingCharacters(in:.whitespaces).isEmpty else{return};let selected=config;let key=Vault.read(selected.text.keyAccount);guard !key.isEmpty else{settingsPage="模型与服务";settings=true;return}
  processing=true;defer{processing=false}
  do {answer=try await Cloud(config:selected).chat(text:transcript,question:question,key:key)} catch{report(error)}
 }
 func export() {
  let panel=NSSavePanel();panel.nameFieldStringValue="会议纪要.md";guard panel.runModal() == .OK,let url=panel.url else{return}
  let body="# \(meeting.title)\n\n## 纪要\n\(meeting.summary)\n\n## 章节\n\(meeting.chapters)\n\n## 思维链\n\(meeting.tree)\n\n## 分歧点\n\(meeting.disagreements ?? "尚未整理")\n\n## 待办\n\(meeting.todos)\n\n## 笔记\n\(meeting.notes)\n\n## 逐字稿\n\(transcript)"
  do{try body.write(to:url,atomically:true,encoding:.utf8)}catch{report(error)}
 }
}
