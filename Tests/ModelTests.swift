import Foundation
import Darwin
@main struct Checks {
 @MainActor static func main() throws {
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
  print("通过：七页真实数据路由、示例隔离、空会议不落盘、新分歧保存、录音时会议切换保护。未调用真实密钥、麦克风或云端。")
 }
}
