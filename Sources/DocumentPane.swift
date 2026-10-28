import SwiftUI
struct DocumentPane:View {
 @ObservedObject var w:Workspace
 let p:Palette
 @Environment(\.accessibilityReduceMotion) private var reduceMotion
 @AppStorage("vt.motionEnabled") private var motionEnabled=true
 @State private var editingSentence:Sentence?
 @State private var followLatest=true
 @State private var pendingSave:Task<Void,Never>?
 var body:some View {
  Group {
   if w.tab=="笔记" {notes}
   else if w.tab=="转写" {transcription}
   else if w.sectionSnapshot.body.isEmpty {emptySection}
   else {ScrollView{VStack(alignment:.leading,spacing:22){
    Text(sectionTitle).font(.system(size:21,weight:.semibold)).padding(.bottom,2)
    if w.tab=="分歧点"{Text("根据会议原文归纳；执行条件和待确认信息不自动等于意见冲突。").font(.callout).foregroundStyle(p.muted)}
    if w.tab=="思维链"{Text("会议讨论脉络：议题、观点、理由、回应与结论。").font(.callout).foregroundStyle(p.muted)}
    DocumentBlocks(text:w.sectionSnapshot.body,p:p,open:{w.revealSource($0)})
    Text("AI整理内容请对照原文核实，点击时间标记可以回听。").font(.caption).foregroundStyle(p.muted)
   }.padding(.top,14).padding(.bottom,32).padding(.horizontal,10).frame(maxWidth:760,alignment:.leading).frame(maxWidth:.infinity)}}
  }.sheet(item:$editingSentence){sentence in SentenceEditor(w:w,sentence:sentence)}.id(w.tab).transition(.opacity).animation(reduceMotion || !motionEnabled ? nil:.easeOut(duration:0.14),value:w.tab)
 }
 private var sectionTitle:String {w.tab=="AI纪要" ? "会议纪要":w.tab}
 private var notes:some View {
  VStack(alignment:.leading,spacing:14){
   Text("我的笔记").font(.system(size:21,weight:.semibold))
   Text("笔记自动保存在本机，可独立编辑和导出。").font(.callout).foregroundStyle(p.muted)
   TextEditor(text:$w.meeting.notes).font(.system(size:15)).lineSpacing(7).scrollContentBackground(.hidden).accessibilityLabel("会议笔记")
    .onChange(of:w.meeting.notes){_ in pendingSave?.cancel();pendingSave=Task{try? await Task.sleep(nanoseconds:450_000_000);if !Task.isCancelled{w.persist()}}}
    .onDisappear{pendingSave?.cancel();w.persist()}
  }.padding(.top,14).padding(.horizontal,10)
 }
 private var transcription:some View {
  ScrollViewReader{proxy in
   ScrollView{LazyVStack(alignment:.leading,spacing:0){
    Text("逐字记录").font(.system(size:21,weight:.semibold)).padding(.top,14).padding(.bottom,10)
    HStack{Toggle("跟随最新文字",isOn:$followLatest).toggleStyle(.checkbox);Button("返回最新"){followLatest=true;proxy.scrollTo("transcript-end",anchor:.bottom)}}.font(.callout)
    Text("结束录音后可逐段纠错、修改发言人；原始录音和修改前版本保留。").font(.callout).foregroundStyle(p.muted).padding(.bottom,20)
    if w.meeting.sentences.isEmpty && w.partial.isEmpty {emptySection}
    ForEach(w.meeting.sentences){s in
     VStack(alignment:.leading,spacing:10){
      HStack(spacing:9){Image(systemName:"person.crop.circle").foregroundStyle(p.actionText);Text(s.speaker).foregroundStyle(p.muted);Button("纠错"){editingSentence=s}.disabled(w.busy);Button(Wire.time(s.start)){w.play(s.start)}.foregroundStyle(p.actionText).buttonStyle(.borderless)}.font(.system(size:12))
      Text(s.text).font(.system(size:15)).lineSpacing(7).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
     }.padding(.vertical,20).padding(.horizontal,12).frame(maxWidth:.infinity,alignment:.leading).background(w.highlightedSentence==s.id ? p.hero:Color.clear).clipShape(RoundedRectangle(cornerRadius:8)).overlay(alignment:.bottom){p.ink.opacity(0.08).frame(height:1)}.id(s.id)
    }
    if !w.partial.isEmpty{Text(w.partial+" ▍").font(.system(size:15)).foregroundStyle(p.muted).lineSpacing(7).padding(15)}
    Color.clear.frame(height:2).id("transcript-end")
   }.padding(.horizontal,8).padding(.bottom,24)}
   .onChange(of:w.partial){_ in if w.phase=="录音中" && followLatest{proxy.scrollTo("transcript-end",anchor:.bottom)}}
   .onChange(of:w.highlightedSentence){id in if let id=id{proxy.scrollTo(id,anchor:.center)}}
   .onAppear{if let id=w.highlightedSentence{DispatchQueue.main.async{proxy.scrollTo(id,anchor:.center)}}}
  }
 }
 private var emptySection:some View {
  VStack(spacing:17){
   Image(systemName:w.tab=="转写" ? "waveform":"doc.text").font(.system(size:30,weight:.light)).foregroundStyle(p.accent.opacity(0.6))
   Text(w.meeting.sentences.isEmpty ? "还没有转写记录":"尚未生成"+w.tab).font(.system(size:20,weight:.medium))
   Text(w.meeting.sentences.isEmpty ? "点击开始录音，确认后的文字会实时显示在这里。":"可点击“更新整理”；启用自动整理后，录音中也会生成实时草稿。").font(.callout).foregroundStyle(p.muted).multilineTextAlignment(.center).frame(maxWidth:380)
   if w.meeting.sentences.isEmpty {Button("查看虚构会议示例"){w.loadDemo()}.buttonStyle(.borderless).disabled(w.busy)}
  }.frame(maxWidth:.infinity).padding(.vertical,65)
 }
}
struct DocumentBlocks:View {
 let text:String
 let p:Palette
 let open:(Double)->Void
 private var blocks:[String]{text.components(separatedBy:"\n\n").map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}.filter{!$0.isEmpty}}
 var body:some View {
  VStack(alignment:.leading,spacing:21){ForEach(Array(blocks.enumerated()),id:\.offset){i,block in
   VStack(alignment:.leading,spacing:9){
    ForEach(Array(block.components(separatedBy:"\n").enumerated()),id:\.offset){_,line in
     let heading=line.hasPrefix("#")
     Text(heading ? line.replacingOccurrences(of:"^#+\\s*",with:"",options:.regularExpression):line)
      .font(.system(size:heading ? 16:15,weight:heading ? .semibold:.regular)).lineSpacing(7).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
    }
    let references=SourceReference.extract(block)
    if !references.isEmpty{ScrollView(.horizontal,showsIndicators:false){HStack(spacing:8){ForEach(references){ref in Button{open(ref.seconds)}label:{Label(ref.label,systemImage:"arrow.up.right").font(.system(size:11)).padding(.horizontal,7).padding(.vertical,4).foregroundStyle(p.actionText).background(p.accent.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius:5))}.buttonStyle(.plain).accessibilityLabel("查看"+ref.label+"的原文")}}}}
   }.frame(maxWidth:.infinity,alignment:.leading).padding(i==0 ? 17:0).background(i==0 ? p.hero.opacity(0.7):Color.clear).clipShape(RoundedRectangle(cornerRadius:8))
  }}
 }
}
