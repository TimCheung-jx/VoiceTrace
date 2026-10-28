import SwiftUI
import AVFoundation
import AppKit
@MainActor final class Workspace: ObservableObject {
 @Published var saveFailed=false
 @Published var revisions:[TextRevision]=[]
 @Published var inputLevel:Float=0
 @Published var saving=false
 private let diskQueue=DispatchQueue(label:"org.voicetrace.app.storage")
 private var saveGeneration=0
 private var deferredSave:Task<Void,Never>?
 @Published var recoveryItems:[RecoveryCandidate]=[]
 @Published var showRecovery=false
 @Published var finalAuto=UserDefaults.standard.object(forKey:"vt.finalAuto") as? Bool ?? true
 @Published var allMeetings=false
 @Published var trash:[Meeting]=[]
 @Published var liveBusy=false
 @Published var liveStatus=""
 @Published var summaryDraft=false
 @Published var paused=false
 @Published var liveEnabled=UserDefaults.standard.object(forKey:"vt.liveEnabled") as? Bool ?? true
 @Published var liveInterval=UserDefaults.standard.object(forKey:"vt.liveInterval") as? Double ?? 30
 var summaryService:((String,Bool) async throws -> SummaryBundle)?
 private var liveTask:Task<Void,Never>?
 private var liveLoop:Task<Void,Never>?
 private var lastLiveText=""
 private var finalPending=false
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
 var busy:Bool {locked || liveBusy}
 var canClose:Bool {!busy && !saveFailed}
 var meetingState:String {phase != "空闲" ? phase:(meeting.captureState=="录音中" ? "异常中断，待核对":meeting.captureState ?? (meeting.recordings.isEmpty ? "未开始":"已有录音"))}
 var aiState:String {liveBusy || liveStatus.contains("未完成") || liveStatus.hasPrefix("请") ? liveStatus:meeting.summaryState=="待更新" ? "逐字稿已更新，需重新整理":(meeting.summaryState == "草稿" ? "实时草稿":meeting.summaryState == "最终" ? "最终整理已保存":liveStatus.isEmpty ? (meeting.summary.isEmpty ? "尚未整理":"已有整理，请核对"):liveStatus)}
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
  root=ProcessInfo.processInfo.environment["VOICETRACE_DATA_DIR"].map { URL(fileURLWithPath:$0,isDirectory:true) } ?? docs.appendingPathComponent(AppIdentity.dataDirectory,isDirectory:true)
  do {try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:root.path)} catch {alert="无法创建资料目录，请检查文稿目录权限"}
  if ProcessInfo.processInfo.environment["VOICETRACE_QA"]=="1"{modelSettings=SettingsFile.fresh();theme=ProcessInfo.processInfo.environment["VOICETRACE_QA_THEME"] ?? "燕麦森林";settingsPage=ProcessInfo.processInfo.environment["VOICETRACE_QA_SETTING_PAGE"] ?? "外观"}
  refresh();scanRecovery()
 }
 func refresh() {
  guard let dirs=try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil) else{return}
  trash=( (try? FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("RecentlyDeleted"),includingPropertiesForKeys:nil)) ?? []).compactMap {try? JSONDecoder().decode(Meeting.self,from:Data(contentsOf:$0.appendingPathComponent("meeting.json")))}
  history=dirs.compactMap {try? JSONDecoder().decode(Meeting.self,from:Data(contentsOf:$0.appendingPathComponent("meeting.json")))}.sorted{$0.created>$1.created}
 }
 func updateHistory(_ item:Meeting){history.removeAll{$0.id==item.id};history.append(item);history.sort{$0.created>$1.created}}
 func schedulePersist(){
  deferredSave?.cancel()
  deferredSave=Task{[weak self] in
   try? await Task.sleep(nanoseconds:500_000_000)
   guard !Task.isCancelled,let self=self else{return}
   let snapshot=self.meeting;let root=self.root
   self.saveGeneration+=1;let generation=self.saveGeneration;self.saving=true
   do{
    try await withCheckedThrowingContinuation{(continuation:CheckedContinuation<Void,Error>) in
     self.diskQueue.async{do{try MeetingDisk.save(snapshot,root:root);continuation.resume()}catch{continuation.resume(throwing:error)}}
    }
    if self.saveGeneration==generation{self.saving=false;self.saveFailed=false;if self.meeting.id==snapshot.id{self.updateHistory(snapshot)}}
   }catch{if self.saveGeneration==generation{self.saving=false;self.saveFailed=true;self.alert="本地保存失败，内容仍在窗口中。请重试保存或导出备份。"}}
  }
 }
 @discardableResult func persist() -> Bool {
  deferredSave?.cancel();saveGeneration+=1;saving=false
  guard meeting.title != "新会议" || !meeting.sentences.isEmpty || !meeting.recordings.isEmpty || !meeting.notes.isEmpty || !meeting.summary.isEmpty else{return true}
  let snapshot=meeting;let root=self.root
  do{try diskQueue.sync{try MeetingDisk.save(snapshot,root:root)};updateHistory(snapshot);saveFailed=false;return true}
  catch{saveFailed=true;alert="本地保存失败。已有内容仍保留在当前窗口，请重试保存或先导出；暂勿退出或切换会议。";return false}
 }
 func newMeeting() {guard !busy,persist() else{return};cancelLive();allMeetings=false;paused=false;stopPlay();playbackPosition=0;highlightedSentence=nil;meeting=Meeting();partial="";answer="";status="新会议 · 可以开始录音"}
 func load(_ item:Meeting) {guard !busy,persist() else{return};cancelLive();allMeetings=false;paused=false;stopPlay();playbackPosition=0;highlightedSentence=nil;meeting=item;paused=item.captureState=="已暂停";summaryDraft=item.summaryState=="草稿" || item.summaryState=="待更新";liveStatus="";partial="";answer="";status="已打开本地会议"}
 func saveSpeechProfile(_ draft:SpeechProfile,key:String) throws {
  guard !locked,!liveBusy else{throw AppError("请等待当前录音或整理结束后再切换配置")}
  let profile=try draft.validated();try Vault.save(profile.keyAccount,key.trimmingCharacters(in:.whitespacesAndNewlines))
  var updated=modelSettings;updated.upsert(profile);try updated.save(.standard);modelSettings=updated;status="语音配置已切换，下一次录音或会后整理生效"
 }
 func saveTextProfile(_ draft:TextProfile,key:String) throws {
  guard !locked,!liveBusy else{throw AppError("请等待当前录音或整理结束后再切换配置")}
  let profile=try draft.validated();try Vault.save(profile.keyAccount,key.trimmingCharacters(in:.whitespacesAndNewlines))
  var updated=modelSettings;updated.upsert(profile);try updated.save(.standard);modelSettings=updated;status="整理配置已切换，下一次生成或问答生效"
 }
 func report(_ error:Error){alert=(error as? AppError)?.message ?? ConnectionDiagnostics.describe(error,stage:"当前操作")}
 func start() async {
  guard !busy,!saveFailed else{return};let selected=config
  do {_=try selected.speech.validated()}catch{report(error);settingsPage="模型与服务";settings=true;return}
  let key=Vault.read(selected.speech.keyAccount);guard !key.isEmpty else{settingsPage="模型与服务";settings=true;return};stopPlay()
  taskID=UUID().uuidString;let attempt=taskID
  phase="连接中";status="正在申请麦克风权限…"
  let allowed=await AVCaptureDevice.requestAccess(for:.audio)
  guard phase=="连接中",taskID==attempt else{return}
  guard allowed else{phase="空闲";alert="请在系统设置 → 隐私与安全性 → 麦克风中允许声迹使用麦克风";return}
  if meeting.title=="新会议"{let formatter=DateFormatter();formatter.dateFormat="yyyy-MM-dd HH:mm";meeting.title="会议 "+formatter.string(from:Date())}
  guard persist() else{phase="空闲";return};offset=meeting.recordings.reduce(0){$0+$1.duration};finalIDs=[];partial="";tab="转写";scheduledPause=false
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
       if sentence["sentence_end"] as? Bool == true {let sid="\(sentence["sentence_id"] ?? "")-\(sentence["begin_time"] ?? 0)";if self.finalIDs.insert(sid).inserted{self.meeting.sentences.append(row);self.schedulePersist()};self.partial=""} else {self.partial=row.text}
      }
     case "task-finished":self.finishConnection();return
     case "task-failed":self.fail(ConnectionDiagnostics.server(header));return
     default:break
     }
    }
   } catch {if !Task.isCancelled && self.taskID==expected && self.phase != "空闲"{self.transportFailed(error,stage:failureStage,httpStatus:(ws.response as? HTTPURLResponse)?.statusCode)}}
  }
 }
 private func beginCapture(ws:URLSessionWebSocketTask) throws {
  guard phase=="连接中",capture==nil else{return}
  var pipe:AsyncStream<Data>.Continuation!
  let stream=AsyncStream<Data>(bufferingPolicy:.bufferingOldest(40)){pipe=$0};continuation=pipe
  let sink=pipe!;let expected=taskID
  sender=Task {
   do {for await data in stream {guard !Task.isCancelled else{return};try await ws.send(.data(data))};if self.taskID==expected && self.phase=="结束中" {try await ws.send(.string(String(data:try Wire.json(Wire.command("finish-task",id:expected)),encoding:.utf8)!))}}
   catch {if self.taskID==expected && self.phase != "空闲"{self.transportFailed(error,stage:"发送实时音频",httpStatus:(ws.response as? HTTPURLResponse)?.statusCode)}}
  }
  let audio=AudioCapture();capture=audio
  try audio.start(directory:folder,offset:offset,yield:{data in
   if case .dropped = sink.yield(data) {Task {@MainActor in if self.taskID==expected && self.phase != "空闲"{self.fail("网络发送速度不足，本段已停止并保存，未发送内容可会后补转写。")}}}
  },level:{value in Task{@MainActor in if self.taskID==expected{self.inputLevel=value}}},interrupted:{Task{@MainActor in if self.taskID==expected{self.deviceChanged()}}},fail:{Task {@MainActor in if self.taskID==expected && self.phase != "空闲"{self.fail("音频转换或写盘失败，本段已停止。请检查输入设备及磁盘空间。")}}})
  paused=false;if !meeting.summary.isEmpty{meeting.summaryState="待更新";summaryDraft=true};meeting.captureState="录音中";persist();startLiveLoop();phase="录音中";status="● 正在录音并实时转写 · 发言人待会后区分"
 }
 private func stopCapture() {
  guard let audio=capture else{return};capture=nil;inputLevel=0
  do {if let (url,duration)=try audio.stop(){meeting.recordings.append(Recording(path:url.path,offset:offset,duration:duration));persist()}} catch {report(error)}
 }
 func stop(pause:Bool=false) {
  if phase=="空闲",paused,!pause {paused=false;meeting.captureState="已结束";persist();if finalAuto{requestLive(final:true)};status="录音已结束并保存";return}
  guard phase=="录音中" else{return};scheduledPause=pause;phase="结束中";stopCapture();continuation?.finish();status="正在等待最后一句识别结果…"
  let expected=taskID;watchdog?.cancel();watchdog=Task {try? await Task.sleep(nanoseconds:20_000_000_000);if !Task.isCancelled,self.taskID==expected,self.phase=="结束中"{self.fail("等待最后结果超时。本地录音和已收到的文字已保存，可会后补转写。")}}
 }
 private func finishConnection() {
  stopCapture()
  watchdog?.cancel();socket?.cancel(with:.normalClosure,reason:nil);socket=nil;sender=nil;receiver=nil;continuation=nil;phase="空闲";partial="";paused=scheduledPause;meeting.captureState=scheduledPause ? "已暂停":"已结束";liveLoop?.cancel();if !scheduledPause && finalAuto{requestLive(final:true)};persist();status=scheduledPause ? "已暂停 · 点击继续录音创建下一段" : "录音已保存 · 可整理发言人或生成纪要"
 }
 private func fail(_ message:String) {
  liveLoop?.cancel()
  let hadCapture=capture != nil
  stopCapture();continuation?.finish();sender?.cancel();receiver?.cancel();watchdog?.cancel();socket?.cancel(with:.goingAway,reason:nil);socket=nil;continuation=nil;phase="空闲";status="操作已停止 · 请查看提示";alert=message+(hadCapture ? "\n已停止采集；请在会议资料目录核对本段录音。":"\n此次尚未开始采集录音。")
  meeting.captureState=meeting.recordings.isEmpty ? "未开始":"待补转写"
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
  guard !locked,!liveBusy,!meeting.recordings.isEmpty else{return};guard meeting.transcriptEdited != true else{alert="逐字稿包含人工纠错，为防止覆盖，请先在修订历史恢复原稿后再执行会后识别。";return};let selected=config;let key=Vault.read(selected.speech.keyAccount);guard !key.isEmpty else{settingsPage="模型与服务";settings=true;return}
  processing=true;defer{processing=false};var updated:[Sentence]=[]
  do {for (i,r) in meeting.recordings.enumerated(){status="正在整理第\(i+1)/\(meeting.recordings.count)段发言人…";var rows=try await Cloud(config:selected).diarize(r,key:key);for j in rows.indices{rows[j].speaker="第\(i+1)段·"+rows[j].speaker};updated+=rows}
   guard !updated.isEmpty else{throw AppError("服务未识别到语音，原逐字稿未更改")}
   let backup=folder.appendingPathComponent("实时原稿-\(UUID().uuidString).json");try JSONEncoder().encode(meeting.sentences).write(to:backup)
   meeting.sentences=updated;meeting.summaryState="待更新";summaryDraft=true;liveStatus="逐字稿已更新，请重新整理";persist();status="发言人整理完成 · 跨录音段身份需人工核对"
  }catch{report(error);status="会后整理未完成 · 原逐字稿保持不变"}
 }
 func generate() async {guard !busy else{return};requestLive(final:true)}
 func ask() async {
  guard !busy,!question.trimmingCharacters(in:.whitespaces).isEmpty else{return};let selected=config;let key=Vault.read(selected.text.keyAccount);guard !key.isEmpty else{settingsPage="模型与服务";settings=true;return}
  processing=true;defer{processing=false}
  let context=QuestionContext.select(transcript:transcript,question:question,overview:meeting.summary)
  do {answer=try await Cloud(config:selected).chat(text:context.text,question:question+(context.partial ? "\n这是长会议的总览及匹配原文片段，并非全部原文。回答必须说明检索范围有限，不得声称穷尽全文。":""),key:key);if context.partial{answer="本次基于会议总览及匹配原文片段，不代表已穷尽全文。\n\n"+answer}} catch{report(error)}
 }
 // 实时整理与录音分别运行；仅发送已经确认的逐字稿。
 func cancelLive(){liveLoop?.cancel();liveTask?.cancel();liveTask=nil;liveBusy=false;lastLiveText="";finalPending=false;summaryDraft=false}
 func startLiveLoop(){
  liveLoop?.cancel()
  liveLoop=Task { [weak self] in
   while !Task.isCancelled {
    guard let self=self else{return}
    try? await Task.sleep(nanoseconds:UInt64(max(15,self.liveInterval)*1_000_000_000))
    guard !Task.isCancelled else{return}
    if self.liveEnabled{self.requestLive()}
   }
  }
 }
 func requestLive(final:Bool=false){
  if final {finalPending=true}
  guard !liveBusy,!processing,!transcript.isEmpty else{return}
  let isFinal=finalPending
  guard isFinal || transcript != lastLiveText else{liveStatus="原文未变化，无需重复整理";return}
  let selected=config;let key=summaryService == nil ? Vault.read(selected.text.keyAccount):""
  guard !key.isEmpty || summaryService != nil else{liveStatus="请在设置中配置整理模型及密钥";return}
  let snapshot=transcript;let cached=meeting.summaryCache ?? [];let through=meeting.sentences.last?.end;let id=meeting.id
  if isFinal && !meeting.summary.isEmpty{guard archiveText("最终整理前") else{return}}
  finalPending=false;liveBusy=true;summaryDraft=true;liveStatus=isFinal ? "正在生成最终整理…":"正在更新实时草稿…"
  liveTask=Task {
   do {
    let run=try await SummaryPipeline.run(text:snapshot,scope:selected.text.id+"|"+selected.text.baseURL+"|"+selected.deepModel,cache:cached,final:isFinal,call:{source,instruction in
     if let service=self.summaryService{return try await service(source,isFinal)}
     return try SummaryBundle.parse(await Cloud(config:selected).chat(text:source,question:instruction,key:key))
    },progress:{cache,stage in
     guard self.meeting.id==id,!Task.isCancelled else{return}
     self.meeting.summaryCache=cache;self.liveStatus=(isFinal ? "最终整理 · ":"实时草稿 · ")+stage;self.schedulePersist()
    })
    let bundle=run.bundle
    guard !Task.isCancelled,self.meeting.id==id else{return}
    self.applyAI(bundle);self.meeting.summaryCache=run.cache;self.meeting.segmentSummaries=run.parts.map{$0.fields}
    self.meeting.summaryState=isFinal ? "最终":"草稿";self.meeting.summaryUpdated=Date();self.meeting.summaryThrough=through;self.meeting.summaryModel=selected.deepModel;self.lastLiveText=snapshot;self.summaryDraft = !isFinal;self.liveStatus=isFinal ? "最终整理完成 · 请核对":"实时草稿已更新";self.persist()
   }catch{if !Task.isCancelled,self.meeting.id==id{self.liveStatus="整理暂未完成，录音不受影响；可重试"}}
   guard !Task.isCancelled,self.meeting.id==id else{return}
   self.liveBusy=false;self.liveTask=nil
   if self.finalPending{self.requestLive(final:true)}
  }
 }
 func applyAI(_ bundle:SummaryBundle){
  meeting.aiSuggestion=bundle.fields
  for (section,key) in Self.sectionKeys where !(meeting.protectedSections ?? []).contains(section){setSection(section,bundle.fields[key] ?? "")}
 }
 static let sectionKeys=["AI纪要":"summary","思维链":"tree","分歧点":"disagreements","章节":"chapters","待办":"todos"]
 func setSection(_ section:String,_ text:String){switch section{case "AI纪要":meeting.summary=text;case "思维链":meeting.tree=text;case "分歧点":meeting.disagreements=text;case "章节":meeting.chapters=text;case "待办":meeting.todos=text;case "笔记":meeting.notes=text;default:break}}
 @discardableResult func archiveText(_ reason:String)->Bool{
  guard persist() else{return false}
  do{let revision=TextRevision(reason:reason,meeting:meeting);try JSONEncoder().encode(revision).write(to:folder.appendingPathComponent("revision-"+revision.id+".json"),options:.atomic);return true}catch{alert="无法保存修订备份，本次修改未执行。";return false}
 }
 @discardableResult func editSection(_ section:String,text:String)->Bool{
  guard !busy,Self.sectionKeys[section] != nil,archiveText("修改"+section) else{return false}
  setSection(section,text);var protected=meeting.protectedSections ?? [];if !protected.contains(section){protected.append(section)};meeting.protectedSections=protected
  return persist()
 }
 @discardableResult func correctSentence(_ id:String,text:String,speaker:String,allSpeaker:Bool)->Bool{
  guard !busy,let index=meeting.sentences.firstIndex(where:{$0.id==id}),!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,archiveText("逐字稿纠错") else{return false}
  let oldSpeaker=meeting.sentences[index].speaker
  meeting.sentences[index].text=text
  let name=speaker.trimmingCharacters(in:.whitespacesAndNewlines)
  if !name.isEmpty{if allSpeaker && oldSpeaker != "待区分发言人"{for i in meeting.sentences.indices where meeting.sentences[i].speaker==oldSpeaker{meeting.sentences[i].speaker=name}}else{meeting.sentences[index].speaker=name}}
  meeting.transcriptEdited=true;meeting.summaryState="待更新";summaryDraft=true;lastLiveText=""
  return persist()
 }
 func loadRevisions(){
  revisions=((try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)) ?? []).filter{$0.lastPathComponent.hasPrefix("revision-")}.compactMap{url in (try? Data(contentsOf:url)).flatMap{try? JSONDecoder().decode(TextRevision.self,from:$0)}}.sorted{$0.date>$1.date}
 }
 @discardableResult func restoreText(_ revision:TextRevision)->Bool{
  guard !busy,revision.meeting.id==meeting.id,archiveText("恢复版本前") else{return false}
  let recordings=meeting.recordings;let state=meeting.captureState
  meeting=revision.meeting;meeting.recordings=recordings;meeting.captureState=state;lastLiveText="";meeting.summaryState="待更新";summaryDraft=true
  return persist()
 }
 @discardableResult func adoptSuggestion(_ section:String)->Bool{
  guard !busy,let key=Self.sectionKeys[section],let text=meeting.aiSuggestion?[key],archiveText("采用AI建议："+section) else{return false}
  setSection(section,text);meeting.protectedSections=(meeting.protectedSections ?? []).filter{$0 != section};return persist()
 }
 func transportFailed(_ error:Error,stage:String,httpStatus:Int?=nil){fail(ConnectionDiagnostics.describe(error,stage:stage,httpStatus:httpStatus))}
 func deviceChanged(){guard phase=="录音中" else{return};fail("输入设备发生变化，本段已停止。请检查麦克风或耳机，确认后继续录音。")}
 func scanRecovery(){recoveryItems=RecoveryCandidate.scan(root:root);if !recoveryItems.isEmpty{showRecovery=true}}
 func recoverAudio(_ candidate:RecoveryCandidate){
  guard !busy,persist() else{return}
  do{
   let url=root.appendingPathComponent(candidate.meetingID).appendingPathComponent("meeting.json")
   var item=try JSONDecoder().decode(Meeting.self,from:Data(contentsOf:url))
   let recording=try candidate.recover()
   if !item.recordings.contains(where:{$0.path==recording.path}){item.recordings.append(recording)}
   item.captureState="待补转写";if !item.summary.isEmpty{item.summaryState="待更新"};item.notes += "\n[恢复录音] 此段尚需会后补转写并核对时间。"
   try JSONEncoder().encode(item).write(to:url,options:.atomic)
   if meeting.id==item.id{meeting=item}
   refresh();recoveryItems=RecoveryCandidate.scan(root:root)
  }catch{alert="录音恢复未完成，原始文件已保留，请检查磁盘空间及目录权限。"}
 }
 func renameMeeting(_ item:Meeting,title:String){
  guard !locked,!liveBusy else{return};let title=title.trimmingCharacters(in:.whitespacesAndNewlines);guard !title.isEmpty else{return}
  guard persist() else{return}
  var updated=meeting.id==item.id ? meeting:item;updated.title=title
  do{try JSONEncoder().encode(updated).write(to:root.appendingPathComponent(item.id).appendingPathComponent("meeting.json"),options:.atomic);if meeting.id==item.id{meeting.title=title};refresh()}catch{report(error)}
 }
 func moveToTrash(_ ids:Set<String>){
  guard !busy else{alert="请先结束录音或等待整理完成";return};guard persist() else{return}
  let target=root.appendingPathComponent("RecentlyDeleted",isDirectory:true)
  do{try FileManager.default.createDirectory(at:target,withIntermediateDirectories:true)}catch{report(error);return}
  var failed:[String]=[];var count=0
  for item in history where ids.contains(item.id){
   do{try FileManager.default.moveItem(at:root.appendingPathComponent(item.id),to:target.appendingPathComponent(item.id));count+=1;if meeting.id==item.id{cancelLive();stopPlay();meeting=Meeting();paused=false}}
   catch{failed.append(item.title)}
  };refresh();batchReport("移入最近删除",count:count,failed:failed)
 }
 func restoreMeeting(_ item:Meeting){restoreMeetings([item.id])}
 func restoreMeetings(_ ids:Set<String>){
  guard !busy else{return};var failed:[String]=[];var count=0
  for item in trash where ids.contains(item.id){
   do{try FileManager.default.moveItem(at:root.appendingPathComponent("RecentlyDeleted").appendingPathComponent(item.id),to:root.appendingPathComponent(item.id));count+=1}catch{failed.append(item.title)}
  };refresh();batchReport("恢复",count:count,failed:failed)
 }
 func permanentlyDelete(_ ids:Set<String>){
  guard !busy else{return};var failed:[String]=[];var count=0
  for item in trash where ids.contains(item.id){
   do{try FileManager.default.removeItem(at:root.appendingPathComponent("RecentlyDeleted").appendingPathComponent(item.id));count+=1}catch{failed.append(item.title)}
  };refresh();batchReport("永久删除",count:count,failed:failed)
 }
 func batchReport(_ action:String,count:Int,failed:[String]){
  status="已"+action+" \(count) 场会议"
  if !failed.isEmpty{alert=action+"成功 \(count) 项，失败 \(failed.count) 项：\n"+failed.joined(separator:"\n")+"\n失败的记录未被本次操作删除，请检查目录权限或文件是否被移动。"}
 }
 func export() {
  let panel=NSSavePanel();panel.nameFieldStringValue="会议纪要.md";guard panel.runModal() == .OK,let url=panel.url else{return}
  let body="# \(meeting.title)\n\n## 纪要\n\(meeting.summary)\n\n## 章节\n\(meeting.chapters)\n\n## 思维链\n\(meeting.tree)\n\n## 分歧点\n\(meeting.disagreements ?? "尚未整理")\n\n## 待办\n\(meeting.todos)\n\n## 笔记\n\(meeting.notes)\n\n## 逐字稿\n\(transcript)"
  do{try body.write(to:url,atomically:true,encoding:.utf8)}catch{report(error)}
 }
}
