import SwiftUI
@MainActor struct SectionEditor:View {
 @ObservedObject var w:Workspace
 let section:String
 @State private var text:String
 @Environment(\.dismiss) private var dismiss
 init(w:Workspace,section:String){self.w=w;self.section=section;_text=State(initialValue:w.sectionSnapshot.body)}
 var body:some View{
  VStack(alignment:.leading,spacing:16){
   DialogTitle(title:"编辑"+section,subtitle:"保存后保护此页，AI新建议需手动采用。修改前版本保存在修订历史中。")
   TextEditor(text:$text).font(.system(size:15)).lineSpacing(6).padding(8).background(Color.white).overlay(RoundedRectangle(cornerRadius:8).strokeBorder(Palette.named(w.theme).border)).accessibilityLabel("编辑"+section)
   HStack{Spacer();Button("取消"){dismiss()}.keyboardShortcut(.cancelAction).buttonStyle(QuietButton(tint:Palette.named(w.theme).ink));Button("保存并保护"){if w.editSection(section,text:text){dismiss()}}.buttonStyle(QuietButton(prominent:true,tint:Palette.named(w.theme).accent)).keyboardShortcut(.defaultAction).disabled(w.busy)}
  }.padding(24).frame(width:720,height:570).background(Palette.named(w.theme).paper).foregroundStyle(Palette.named(w.theme).ink)
 }
}
@MainActor struct SentenceEditor:View {
 @ObservedObject var w:Workspace
 let sentence:Sentence
 @State private var text:String
 @State private var speaker:String
 @State private var all=false
 @Environment(\.dismiss) private var dismiss
 init(w:Workspace,sentence:Sentence){self.w=w;self.sentence=sentence;_text=State(initialValue:sentence.text);_speaker=State(initialValue:sentence.speaker)}
 var body:some View{
  VStack(alignment:.leading,spacing:16){
   DialogTitle(title:"逐字稿纠错",subtitle:"原文时间 "+Wire.time(sentence.start)+"，修改不影响原始录音。")
   FormField(title:"发言人标签"){TextField("发言人姓名或标签",text:$speaker).textFieldStyle(.roundedBorder)}
   Toggle("同步修改同一发言标签的其他段落",isOn:$all).disabled(sentence.speaker=="待区分发言人")
   TextEditor(text:$text).font(.system(size:15)).lineSpacing(6).padding(8).background(Color.white).overlay(RoundedRectangle(cornerRadius:8).strokeBorder(Palette.named(w.theme).border)).accessibilityLabel("修正逐字稿")
   Text("保留原始录音与修改前版本；修正后整理标记为待更新。未区分的发言人不能批量认定为同一人。").font(.callout).foregroundStyle(Color.primary.opacity(0.72))
   HStack{Spacer();Button("取消"){dismiss()}.keyboardShortcut(.cancelAction).buttonStyle(QuietButton(tint:Palette.named(w.theme).ink));Button("保存纠错"){if w.correctSentence(sentence.id,text:text,speaker:speaker,allSpeaker:all){dismiss()}}.buttonStyle(QuietButton(prominent:true,tint:Palette.named(w.theme).accent)).keyboardShortcut(.defaultAction).disabled(w.busy || text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
  }.padding(24).frame(width:680,height:460).background(Palette.named(w.theme).paper).foregroundStyle(Palette.named(w.theme).ink)
 }
}
@MainActor struct SuggestionView:View {
 @ObservedObject var w:Workspace
 let section:String
 @State private var confirm=false
 @Environment(\.dismiss) private var dismiss
 var suggestion:String{w.meeting.aiSuggestion?[Workspace.sectionKeys[section] ?? ""] ?? "尚无AI建议"}
 var body:some View{
  VStack(alignment:.leading,spacing:16){
   DialogTitle(title:"比较AI建议",subtitle:section+"：左侧为当前内容，右侧为AI新建议。")
   HStack(alignment:.top){column("当前内容",w.sectionSnapshot.body);column("AI新建议",AnalysisNode.plain(suggestion))}
   Text("采用前会备份当前文字，采用后解除此页人工保护。也可取消并继续保留人工版本。").font(.callout).foregroundStyle(Color.primary.opacity(0.72))
   HStack{Spacer();Button("保留当前版本"){dismiss()};Button("采用AI建议"){confirm=true}.disabled(w.busy || w.meeting.aiSuggestion==nil)}
  }.padding(24).frame(width:950,height:600).background(Palette.named(w.theme).paper).foregroundStyle(Palette.named(w.theme).ink).confirmationDialog("采用AI建议并解除这一页的人工保护？",isPresented:$confirm){Button("采用并备份当前版本"){if w.adoptSuggestion(section){dismiss()}}}
 }
 func column(_ title:String,_ body:String)->some View{VStack(alignment:.leading){Text(title).font(.headline);ScrollView{Text(body).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}}.frame(maxWidth:.infinity)}
}
@MainActor struct RevisionView:View {
 @ObservedObject var w:Workspace
 @State private var selected:TextRevision?
 @Environment(\.dismiss) private var dismiss
 var body:some View{
  VStack(alignment:.leading,spacing:16){
   DialogTitle(title:"修订历史",subtitle:"预览修改前的文字，或恢复到所选版本。")
   Text("恢复会替换该版本的文字及保护设置，当前文字会先备份；现有录音文件保留。").foregroundStyle(Color.primary.opacity(0.72))
   List(w.revisions){revision in RevisionRow(revision:revision,disabled:w.busy){selected=revision}}
   HStack{if w.revisions.isEmpty{Text("尚无人工修订记录").foregroundStyle(Color.primary.opacity(0.72))};Spacer();Button("完成"){dismiss()}.buttonStyle(QuietButton(prominent:true,tint:Palette.named(w.theme).accent))}
  }.padding(24).frame(width:800,height:550).background(Palette.named(w.theme).paper).foregroundStyle(Palette.named(w.theme).ink).onAppear{w.loadRevisions()}.confirmationDialog("恢复所选版本的全部文字？",isPresented:Binding(get:{selected != nil},set:{if !$0{selected=nil}})){Button("备份当前文字并恢复"){if let revision=selected,w.restoreText(revision){w.loadRevisions()};selected=nil}}
 }
}
@MainActor struct SegmentView:View {
 @ObservedObject var w:Workspace
 @Environment(\.dismiss) private var dismiss
 var body:some View{
  VStack(alignment:.leading,spacing:16){DialogTitle(title:"分段整理",subtitle:"查看各段的详细整理及已有时间出处。");Text("这里保留各段的详细整理，会议总览为合并摘要。关键内容请回到逐字稿核对。").foregroundStyle(Color.primary.opacity(0.72))
   ScrollView{LazyVStack(alignment:.leading,spacing:20){ForEach(Array((w.meeting.segmentSummaries ?? []).enumerated()),id:\.offset){index,fields in SegmentCard(index:index,fields:fields)}}}
   HStack{Spacer();Button("完成"){dismiss()}.buttonStyle(QuietButton(prominent:true,tint:Palette.named(w.theme).accent))}
  }.padding(24).frame(width:800,height:600).background(Palette.named(w.theme).paper).foregroundStyle(Palette.named(w.theme).ink)
 }
}

@MainActor private struct RevisionRow:View {
 let revision:TextRevision
 let disabled:Bool
 let restore:()->Void
 var preview:String{let rows=revision.meeting.sentences.map{sentence in "["+Wire.time(sentence.start)+"] "+sentence.speaker+"："+sentence.text};return AnalysisNode.plain(revision.meeting.summary)+"\n\n"+rows.joined(separator:"\n")}
 var body:some View{
  DisclosureGroup{
   ScrollView{Text(preview).textSelection(.enabled)}.frame(maxHeight:200)
   Button("恢复此版本文字",action:restore).disabled(disabled)
  }label:{HStack{Text(revision.reason);Spacer();Text(revision.date,style:.date);Text(revision.date,style:.time)}}
 }
}
@MainActor private struct SegmentCard:View {
 let index:Int
 let fields:[String:String]
 var body:some View{
  VStack(alignment:.leading,spacing:12){
   Text("第 \(index+1) 段").font(.title3.bold())
   ForEach(["AI纪要","思维链","分歧点","章节","待办"],id:\.self){title in VStack(alignment:.leading,spacing:6){Text(title).font(.headline);Text(AnalysisNode.plain(fields[Workspace.sectionKeys[title] ?? ""] ?? "")).textSelection(.enabled)}}
   Divider()
  }
 }
}
