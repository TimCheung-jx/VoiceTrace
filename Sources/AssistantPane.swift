import SwiftUI
struct AssistantPane:View {
 @ObservedObject var w:Workspace
 let p:Palette
 let close:()->Void
 var body:some View {
  VStack(alignment:.leading,spacing:12){
   HStack{Image(systemName:"sparkle").foregroundStyle(p.actionText);Text("会议助手").font(.system(size:14,weight:.semibold));Spacer();Button(action:close){Image(systemName:"sidebar.right")}.buttonStyle(.plain).help("收起AI助手").accessibilityLabel("收起AI助手")}
   Text("根据逐字稿回答，重要内容附原文时间。").font(.system(size:13)).foregroundStyle(p.muted).lineSpacing(5)
   VStack(spacing:9){
    quick("本次会议有哪些决定？")
    quick("与会人员有哪些明确分歧？请区分意见冲突、执行条件与待确认信息。",label:"本次会议有哪些分歧？")
    quick("请整理接下来要做的事，列出负责人、期限和出处。",label:"接下来需要做什么？")
   }
   HStack(spacing:8){Button{Task{await w.generate()}}label:{Label("整理会议",systemImage:"text.badge.checkmark")}.buttonStyle(QuietButton(tint:p.actionText)).disabled(w.busy || w.meeting.sentences.isEmpty)
    Menu{Button("会后区分发言人 / 补全转写"){Task{await w.diarize()}}.disabled(w.busy || w.meeting.recordings.isEmpty);Button("模型与服务设置"){w.settingsPage="模型与服务";w.settings=true}}label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("更多会议处理操作")
   }
   if w.processing{HStack{ProgressView().controlSize(.small);Text("正在处理，请稍候…").font(.caption).foregroundStyle(p.muted)}}
   if w.answer.isEmpty{Spacer(minLength:8)}else{ScrollView{DocumentBlocks(text:w.answer,p:p,open:{w.revealSource($0)}).font(.callout)}.frame(maxHeight:.infinity)}
   VStack(alignment:.leading,spacing:8){Text("询问本次会议").font(.system(size:13)).foregroundStyle(p.muted)
    TextEditor(text:$w.question).font(.system(size:13)).scrollContentBackground(.hidden).frame(minHeight:50,maxHeight:90).accessibilityLabel("向会议助手提问")
    HStack{Text("基于当前逐字稿").font(.system(size:13)).foregroundStyle(p.muted);Spacer();Button{Task{await w.ask()}}label:{Image(systemName:"arrow.up").frame(width:25,height:25).foregroundStyle(.white).background(p.accent).clipShape(RoundedRectangle(cornerRadius:6))}.buttonStyle(.plain).disabled(w.busy || w.question.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || w.meeting.sentences.isEmpty).accessibilityLabel("发送问题")}
   }.padding(12).background(.white).clipShape(RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).strokeBorder(p.ink.opacity(0.1)))
   Text("AI输出请对照原文核对。").font(.system(size:13)).foregroundStyle(p.muted).lineSpacing(4)
  }.padding(.leading,20).padding(.top,8).overlay(alignment:.leading){p.ink.opacity(0.09).frame(width:1)}
 }
 private func quick(_ question:String,label:String?=nil)->some View {
  Button{w.question=question;Task{await w.ask()}}label:{HStack{Text(label ?? question).multilineTextAlignment(.leading);Spacer();Image(systemName:"arrow.right").font(.system(size:13)).foregroundStyle(p.muted)}.font(.system(size:13)).padding(10).frame(maxWidth:.infinity,alignment:.leading).background(.white).clipShape(RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).strokeBorder(p.ink.opacity(0.1)))}.buttonStyle(.plain).disabled(w.busy || w.meeting.sentences.isEmpty)
 }
}
