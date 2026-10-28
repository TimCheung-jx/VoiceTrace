import SwiftUI
import AppKit
@main struct VoiceTraceApp:App {
 @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
 @StateObject private var w=Workspace()
 private var qaScene:String{ProcessInfo.processInfo.environment["VOICETRACE_QA"]=="1" ? (ProcessInfo.processInfo.environment["VOICETRACE_QA_SCENE"] ?? ""):""}
 @ViewBuilder private var content:some View{
  Group{if qaScene=="settings"{ConfigurationView(w:w)}else if qaScene=="editor"{SectionEditor(w:w,section:"AI纪要")}else{Workbench(w:w)}}.id(qaScene=="editor" ? w.meeting.id:"workspace")
 }

 var body:some Scene {
  WindowGroup("声迹 (VoiceTrace)"){
   content.preferredColorScheme(.light).onAppear{
    AppDelegate.workspace=w
    NSApp.setActivationPolicy(.regular);NSApp.activate(ignoringOtherApps:true)
    NSApp.windows.first(where:{$0.contentView != nil})?.delegate=delegate
    if ProcessInfo.processInfo.environment["VOICETRACE_QA"]=="1"{QARender.prepare(w)}
   }
  }.defaultSize(width:1280,height:840)
  .commands{
   CommandGroup(replacing:.appSettings){Button("声迹设置…"){w.settings=true}.keyboardShortcut(",")}
   CommandGroup(replacing:.newItem){Button("新建会议"){w.newMeeting()}.keyboardShortcut("n").disabled(w.busy)}
  }
 }
}
@MainActor final class AppDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
 static var workspace:Workspace?
 func windowShouldClose(_ sender:NSWindow)->Bool {if let w=Self.workspace,w.busy{w.alert="请先结束录音或等待当前任务完成，再关闭窗口。";return false};if let w=Self.workspace,!w.persist(){return false};return true}
 func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
  guard let w=Self.workspace else{return .terminateNow}
  if w.busy{w.alert="请先结束录音或等待当前处理完成，再退出应用。";return .terminateCancel}
  guard w.persist() else{return .terminateCancel};Vault.clearMemory();return .terminateNow
 }
 func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
}
