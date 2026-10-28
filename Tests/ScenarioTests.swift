import Foundation
import Darwin
@main struct ScenarioChecks {
 @MainActor static func main() async throws {
  let directory=URL(fileURLWithPath:"/private/tmp/voicetrace-scenarios-"+UUID().uuidString)
  setenv("VOICETRACE_DATA_DIR",directory.path,1)
  let small=SummaryBundle(summary:"测试决定 [00:01]",tree:"测试讨论脉络",disagreements:"未发现明确分歧",chapters:"章节 [00:01]",todos:"任务未明确")
  // 四小时的虚构时间轴；不是四小时真实运行或麦克风测试。
  let rows=(0..<4800).map{index in "[\(Wire.time(Double(index)*3))] 测试发言人：第\(index)项虚构事项，确认方案并记录待办，同时核对负责人和时间，所有内容均为虚构。"}
  let transcript=rows.joined(separator:"\n")
  precondition(transcript.count>180000)
  var calls=0;var largest=0;var checkpoints:[SummaryCache]=[]
  let call:(String,String) async throws -> SummaryBundle={source,_ in calls+=1;largest=max(largest,source.count);return small}
  let first=try await SummaryPipeline.run(text:transcript,scope:"mock",cache:[],final:false,call:call,progress:{cache,_ in checkpoints=cache})
  precondition(first.parts.count>10 && largest<15000 && !checkpoints.isEmpty)
  let originalCalls=calls
  let identical=try await SummaryPipeline.run(text:transcript,scope:"mock",cache:first.cache,final:false,call:call,progress:{_,_ in})
  precondition(calls==originalCalls && identical.bundle==small)
  _=try await SummaryPipeline.run(text:transcript+"\n[240:01] 测试人员：新增事项。",scope:"mock",cache:first.cache,final:false,call:call,progress:{_,_ in})
  precondition(calls-originalCalls<originalCalls)
  // 缓存跨磁盘往返；原文纠错应使相关分段失效。
  let stored=try JSONDecoder().decode([SummaryCache].self,from:JSONEncoder().encode(first.cache))
  let beforeCorrection=calls
  _=try await SummaryPipeline.run(text:transcript.replacingOccurrences(of:"第0项",with:"纠正后的第0项"),scope:"mock",cache:stored,final:false,call:call,progress:{_,_ in})
  precondition(calls>beforeCorrection)
  let context=QuestionContext.select(transcript:transcript,question:"第320项是什么？",overview:"虚构总览")
  precondition(context.partial && context.text.count<37000)
  // 第二段失败，第一次已完成分段仍可重用。
  var attempt=0;var partialCache:[SummaryCache]=[]
  do{_=try await SummaryPipeline.run(text:transcript,scope:"retry",cache:[],final:false,call:{source,_ in attempt+=1;if attempt==2{throw URLError(.networkConnectionLost)};return small},progress:{cache,_ in partialCache=cache});preconditionFailure("应模拟失败")}catch{}
  precondition(!partialCache.isEmpty)
  var retries=0
  _=try await SummaryPipeline.run(text:transcript,scope:"retry",cache:partialCache,final:false,call:{_,_ in retries+=1;return small},progress:{_,_ in})
  precondition(retries<originalCalls)
  let cancelled=Task{try await SummaryPipeline.run(text:transcript,scope:"cancel",cache:[],final:false,call:{_,_ in small},progress:{_,_ in})}
  cancelled.cancel();do{_=try await cancelled.value;preconditionFailure("取消不应继续")}catch{}
  var oversizedAttempts=0
  do{_=try await SummaryPipeline.run(text:"[00:00] 虚构内容",scope:"limit",cache:[],final:false,call:{_,_ in oversizedAttempts+=1;return SummaryBundle(summary:String(repeating:"长",count:5000),tree:"脉络",disagreements:"无",chapters:"章节",todos:"任务")},progress:{_,_ in});preconditionFailure("过长输出应拒绝")}catch{}
  precondition(oversizedAttempts==2)
  print("通过：四小时虚构时间轴分段、请求有界、缓存复用、增量更新、纠错失效、失败续作、取消及长会议检索。调用数 \(originalCalls)，最大输入 \(largest) 字符。")

  let w=Workspace();w.meeting.title="虚构修订测试";w.meeting.sentences=[Sentence(start:1,end:2,text:"原始语句",speaker:"发言人1"),Sentence(start:3,end:4,text:"另一句",speaker:"发言人1")];w.meeting.summary="AI原稿";precondition(w.persist())
  let sentenceID=w.meeting.sentences[0].id
  precondition(w.correctSentence(sentenceID,text:"修正后的语句",speaker:"测试甲",allSpeaker:true))
  precondition(w.meeting.sentences.allSatisfy{$0.speaker=="测试甲"} && w.meeting.summaryState=="待更新")
  precondition(w.editSection("AI纪要",text:"人工保留版本"))
  w.applyAI(small);precondition(w.meeting.summary=="人工保留版本" && w.meeting.tree==small.tree)
  precondition(w.adoptSuggestion("AI纪要") && w.meeting.summary==small.summary && !(w.meeting.protectedSections ?? []).contains("AI纪要"))
  w.loadRevisions();precondition(w.revisions.count>=3)
  let earliest=w.revisions.last!
  precondition(w.restoreText(earliest) && w.meeting.sentences[0].text=="原始语句")
  // 保存失败时不得执行未备份的人工修改。
  w.newMeeting();w.meeting.title="虚构备份失败"
  FileManager.default.createFile(atPath:w.folder.path,contents:Data())
  precondition(!w.editSection("AI纪要",text:"不应写入") && w.meeting.summary.isEmpty)

  let route=Workspace();route.meeting.title="虚构设备切换";route.meeting.sentences=[Sentence(start:0,end:1,text:"保留的逐字稿")];route.meeting.recordings=[Recording(path:"test.wav",offset:0,duration:1)];route.persist()
  route.phase="录音中";route.deviceChanged()
  precondition(route.phase=="空闲" && route.meeting.captureState=="待补转写" && route.meeting.sentences.count==1 && route.meeting.recordings.count==1)
  route.phase="录音中";route.transportFailed(URLError(.networkConnectionLost),stage:"接收实时转写")
  precondition(route.phase=="空闲" && route.alert.contains("网络") && route.meeting.sentences.count==1)
  // 子进程异常退出，只写入虚构静音PCM，不使用真实麦克风。
  let crash=Workspace();crash.meeting.title="虚构崩溃恢复";precondition(crash.persist())
  let crashPCM=crash.folder.appendingPathComponent("audio-crash.pcm")
  try JSONEncoder().encode(CaptureJournal(offset:14)).write(to:crashPCM.appendingPathExtension("capture.json"))
  let child=Process();child.executableURL=URL(fileURLWithPath:"/usr/bin/env");child.arguments=["python3","-c","import os,sys; f=os.open(sys.argv[1],os.O_WRONLY|os.O_CREAT,0o600); os.write(f,bytes(32000)); os._exit(9)",crashPCM.path]
  try child.run();child.waitUntilExit();precondition(child.terminationStatus==9)
  let restarted=Workspace();precondition(restarted.showRecovery && restarted.recoveryItems.count==1)
  restarted.recoverAudio(restarted.recoveryItems[0]);precondition(restarted.recoveryItems.isEmpty)
  let recovered=restarted.history.first{$0.id==crash.meeting.id}!
  precondition(recovered.recordings.count==1 && recovered.recordings[0].offset==14 && recovered.captureState=="待补转写")
  print("通过：虚构录音写入进程异常退出后，重启检测并恢复已写盘部分；原件保留。")
  let batch=Workspace();var valid=Meeting();valid.title="虚构批量成功项";try MeetingDisk.save(valid,root:batch.root)
  var missing=Meeting();missing.title="虚构批量缺失项";batch.refresh();batch.history.append(missing)
  batch.moveToTrash([valid.id,missing.id]);precondition(batch.alert.contains("失败 1 项") && batch.trash.contains{$0.id==valid.id})
  // 模拟模型响应阻塞时结束录音，最终请求必须接续处理新增原文。
  let inFlight=Workspace();inFlight.meeting.title="虚构任务接续";inFlight.meeting.sentences=[Sentence(start:0,end:1,text:"首句")];inFlight.phase="录音中"
  var gate:CheckedContinuation<Void,Never>?;var callsInFlight=0
  inFlight.summaryService={_,_ in callsInFlight+=1;if callsInFlight==1{await withCheckedContinuation{gate=$0}};return small}
  inFlight.requestLive();while gate==nil{await Task.yield()}
  inFlight.meeting.sentences.append(Sentence(start:1,end:2,text:"最后新增一句"));inFlight.phase="空闲";inFlight.requestLive(final:true);precondition(inFlight.liveBusy && !inFlight.canClose)
  gate?.resume();while inFlight.liveBusy{await Task.yield()}
  precondition(inFlight.meeting.summaryState=="最终" && inFlight.meeting.summaryThrough==2 && callsInFlight>=3)
  // 关闭自动整理不阻止手动生成；模拟服务无需真实凭据。
  inFlight.liveEnabled=false;inFlight.finalAuto=false;inFlight.meeting.sentences.append(Sentence(start:2,end:3,text:"手动补充"));inFlight.requestLive(final:true)
  while inFlight.liveBusy{await Task.yield()};precondition(inFlight.meeting.summaryThrough==3)
  let writer=Workspace();writer.meeting.title="虚构异步保存";writer.meeting.notes="旧内容";writer.schedulePersist()
  try await Task.sleep(nanoseconds:600_000_000);writer.meeting.notes="最新内容";precondition(writer.persist())
  try await Task.sleep(nanoseconds:50_000_000)
  let disk=try JSONDecoder().decode(Meeting.self,from:Data(contentsOf:writer.folder.appendingPathComponent("meeting.json")))
  precondition(disk.notes=="最新内容")
  print("通过：后台保存与同步落盘的先后顺序，旧快照不会覆盖最新文字。")
  print("通过：逐字稿纠错、发言人同步、人工页保护、AI建议采用、修订恢复、备份失败保护、设备事件和断网事件处理。未录音、未联网。")
 }
}
