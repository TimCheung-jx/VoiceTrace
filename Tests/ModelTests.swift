import Foundation
import Darwin
@main struct Checks {
 @MainActor static func main() async throws {
  let folder=URL(fileURLWithPath:"/private/tmp/voicetrace-model-tests-"+UUID().uuidString)
  setenv("VOICETRACE_DATA_DIR",folder.path,1)
  let w=Workspace();precondition(w.history.isEmpty)
  w.persist();precondition(w.history.isEmpty)
  w.loadDemo();precondition(w.meeting.title.contains("虚构") && !w.history.isEmpty)
  let expected:[String:String]=["转写":w.transcript,"笔记":w.meeting.notes,"AI纪要":w.meeting.summary,"思维链":w.meeting.tree,"分歧点":w.meeting.disagreements!,"章节":w.meeting.chapters,"待办":w.meeting.todos]
  for (tab,body) in expected {w.tab=tab;precondition(w.sectionSnapshot.body==body && !body.isEmpty)}
  let saved=try JSONDecoder().decode(Meeting.self,from:Data(contentsOf:w.folder.appendingPathComponent("meeting.json")))
  precondition(saved.disagreements==w.meeting.disagreements)
  w.phase="录音中";let id=w.meeting.id;w.newMeeting();precondition(w.meeting.id==id)
  w.phase="空闲";w.newMeeting();precondition(w.meeting.id != id && w.meeting.sentences.isEmpty)
  precondition(w.root.standardizedFileURL.path==folder.standardizedFileURL.path)
  w.meeting.sentences=[Sentence(start:0,end:1,text:"测试实时整理")]
  w.phase="录音中"
  w.summaryService={text,final in precondition(!text.isEmpty);return SummaryBundle(summary:final ? "最终":"草稿",tree:"脉络",disagreements:"未发现明确分歧",chapters:"章节",todos:"待办")}
  w.requestLive()
  while w.liveBusy{await Task.yield()}
  precondition(w.meeting.summary=="草稿" && w.summaryDraft && w.phase=="录音中")
  w.phase="空闲";w.requestLive(final:true)
  while w.liveBusy{await Task.yield()}
  precondition(w.meeting.summary=="最终" && !w.summaryDraft)
  w.summaryService={_,_ in throw AppError("模拟失败")};w.requestLive(final:true)
  while w.liveBusy{await Task.yield()}
  precondition(w.meeting.summary=="最终" && w.liveStatus.contains("重试"))
  print("通过：录音中并发整理、草稿、最终整理、失败保留旧结果。未联网。")
  let item=w.history[0];let baseline=w.history.count
  w.renameMeeting(item,title:"测试重命名");precondition(w.history.first?.title=="测试重命名")
  w.phase="录音中";w.moveToTrash([item.id]);precondition(w.history.count==baseline)
  w.phase="空闲";w.alert="";w.moveToTrash([item.id]);precondition(w.history.count==baseline-1 && w.trash.count==1)
  let reload=Workspace();precondition(reload.trash.count==1 && reload.history.count==baseline-1)
  w.restoreMeeting(w.trash[0]);precondition(w.history.count==baseline && w.trash.isEmpty)
  w.moveToTrash([item.id]);w.permanentlyDelete([item.id]);precondition(w.trash.isEmpty)
  w.paused=true;w.stop();precondition(!w.paused && w.phase=="空闲")
  print("通过：重命名、录音删除保护、移入最近删除、重新加载、恢复、永久删除和暂停后结束。")
  // 仅用临时目录构造未完成音频，不访问麦克风或真实资料。
  w.newMeeting();w.meeting.title="虚构恢复测试";w.meeting.captureState="已暂停";w.meeting.summary="待核对草稿";w.meeting.summaryState="草稿";w.meeting.summaryUpdated=Date();w.meeting.summaryThrough=12
  precondition(w.persist())
  let stateCopy=try JSONDecoder().decode(Meeting.self,from:Data(contentsOf:w.folder.appendingPathComponent("meeting.json")))
  w.load(stateCopy);precondition(w.paused && w.summaryDraft && w.aiState=="实时草稿")
  w.liveBusy=true;precondition(!w.canClose);w.liveBusy=false;precondition(w.canClose)
  let pcm=w.folder.appendingPathComponent("audio-test.pcm")
  try Data(repeating:0,count:32000).write(to:pcm)
  try JSONEncoder().encode(CaptureJournal(offset:12)).write(to:pcm.appendingPathExtension("capture.json"))
  w.scanRecovery();precondition(w.recoveryItems.count==1 && w.showRecovery)
  w.recoverAudio(w.recoveryItems[0]);precondition(w.recoveryItems.isEmpty && w.meeting.recordings.count==1 && w.meeting.recordings[0].offset==12)
  precondition(FileManager.default.fileExists(atPath:pcm.path))
  let wav=try Data(contentsOf:URL(fileURLWithPath:w.meeting.recordings[0].path))
  precondition(wav.count==32044 && wav.prefix(44)==Wire.wavHeader(bytes:32000))
  w.scanRecovery();precondition(w.recoveryItems.isEmpty)
  w.finalAuto=false;w.paused=true;w.summaryService={_,_ in preconditionFailure("关闭自动最终整理后不应调用")};w.stop();precondition(!w.liveBusy && w.meeting.captureState=="已结束")
  // 模拟目录不可写：目标位置是一份普通文件。失败不允许切换会议。
  w.newMeeting();w.meeting.title="虚构保存失败测试"
  FileManager.default.createFile(atPath:w.folder.path,contents:Data())
  precondition(!w.persist() && w.saveFailed && !w.canClose)
  let failedID=w.meeting.id;w.newMeeting();precondition(w.meeting.id==failedID)
  try FileManager.default.moveItem(at:w.folder,to:w.root.appendingPathComponent("simulated-blocker"))
  precondition(w.persist() && !w.saveFailed && w.canClose)
  print("通过：状态持久化、最终整理退出保护、PCM恢复与幂等、保留原件、保存失败保护。")
  print("通过：七页真实数据路由、示例隔离、空会议不落盘、新分歧保存、录音时会议切换保护。未调用真实密钥、麦克风或云端。")
 }
}
