import SwiftUI
import AppKit
struct DemoMeeting {
 static func make()->Meeting {
  var m=Meeting();m.title="产品试点项目周例会（虚构演示）"
  m.sentences=[Sentence(start:0,end:15,text:"今天主要确认试点范围、首轮交付和验收安排。先选择两个内部团队试用，跑通核心流程。",speaker:"项目负责人"),Sentence(start:156,end:173,text:"建议先完成电脑端的核心页面，手机端后续扩展。试点期间收集具体使用障碍。",speaker:"设计"),Sentence(start:382,end:401,text:"自动整理需要接入云端服务，接口稳定性还需验证，暂时不能承诺正式上线日期。",speaker:"研发"),Sentence(start:655,end:680,text:"确定两个团队参与电脑端试点。设计周三提供页面稿，研发周五给出验证结果，正式上线时间验证后再定。",speaker:"项目负责人"),Sentence(start:1040,end:1059,text:"验收标准先拟草案，具体指标下次确认。",speaker:"设计")]
  m.summary="""
  核心结论
  两个内部团队参与首轮电脑端试点。正式上线时间在接口验证完成后另行确定。[10:55]

  ## 01　已形成的决定
  首轮聚焦电脑端核心流程，手机端留待后续扩展。[02:36] [10:55]

  ## 02　接下来要做的事
  设计周三提供页面稿，研发周五提交接口验证结果。[10:55]

  ## 03　尚待确认
  验收指标和正式上线日期尚未确定，不能将建议写成最终决定。[17:20]
  """
  m.tree="""
  ## 试点范围
  观点：项目负责人建议选择两个内部团队试用。[00:00]
  补充：设计建议先完成电脑端，手机端后续扩展。[02:36]
  回应与结论：确定首轮电脑端试点。[10:55]

  ## 技术与上线时间
  条件：研发指出接口稳定性还需验证。[06:22]
  结论：验证后再定正式上线日期。[10:55]
  """
  m.disagreements="""
  未发现明确分歧。
  原文未记录相互对立的主张。以下事项属于执行条件和待确认信息，不应认定为人员冲突。

  ## 执行条件：上线时间
  研发：接口稳定性尚待验证。[06:22]
  项目负责人：先提交验证结果，再确定正式上线时间。[10:55]
  当前状态：形成先验证、后确定日期的处理安排。

  ## 信息待确认：验收指标
  设计建议先拟验收草案，具体指标下次确认，未记录反对意见。[17:20]
  """
  m.chapters="""
  ## 试点范围与目标 [00:00]
  明确参与团队及首轮核心流程。

  ## 设计安排 [02:36]
  电脑端优先，记录具体使用障碍。

  ## 技术验证 [06:22]
  讨论接口稳定性及交付约束。

  ## 决定与分工 [10:55]
  明确页面稿、验证结果和上线安排。

  ## 验收标准 [17:20]
  具体指标下次确认。
  """
  m.todos="设计：周三提供电脑端页面稿。[10:55]\n\n研发：周五提交接口验证结果。[10:55]\n\n设计：拟定验收标准草案，期限未明确。[17:20]"
  m.notes="[10:55] 首轮只做电脑端，注意保留接口验证结果。\n\n需要追问：验收指标由谁最终确认？"
  return m
 }
}
extension Workspace {
 func loadDemo(){guard !locked else{return};persist();stopPlay();meeting=DemoMeeting.make();tab="AI纪要";status="虚构会议示例 · 未连接云端，未附录音";answer="";partial="";playbackPosition=0;persist()}
}
@MainActor enum QARender {
 private static var prepared=false
 static func prepare(_ w:Workspace){
  guard !prepared else{return};prepared=true
  w.meeting=DemoMeeting.make();w.history=[w.meeting];w.tab=ProcessInfo.processInfo.environment["VOICETRACE_QA_TAB"] ?? "AI纪要";w.status="虚构会议 · 原生Mac界面检查"
  w.modelSettings=SettingsFile.fresh();w.theme=ProcessInfo.processInfo.environment["VOICETRACE_QA_THEME"] ?? "燕麦森林"
  if ProcessInfo.processInfo.environment["VOICETRACE_QA_SCENE"]=="library"{w.allMeetings=true;w.paused=true;w.meeting.captureState="已暂停"}
  guard let output=ProcessInfo.processInfo.environment["VOICETRACE_QA_SCREENSHOT"] else{return}
  DispatchQueue.main.asyncAfter(deadline:.now()+1.5){
   guard let window=NSApp.windows.first(where:{$0.contentView != nil}),let view=window.contentView else{return}
   window.setContentSize(NSSize(width:Double(ProcessInfo.processInfo.environment["VOICETRACE_QA_WIDTH"] ?? "1440") ?? 1440,height:820));window.makeFirstResponder(nil);window.layoutIfNeeded()
   DispatchQueue.main.asyncAfter(deadline:.now()+0.5){
    guard let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{return};view.cacheDisplay(in:view.bounds,to:rep)
    if let data=rep.representation(using:.png,properties:[:]){try? data.write(to:URL(fileURLWithPath:output))}
    NSApp.terminate(nil)
   }
  }
 }
}
