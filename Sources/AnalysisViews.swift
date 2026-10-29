import SwiftUI

struct AnalysisPage:View {
 @ObservedObject var w:Workspace
 let nodes:[AnalysisNode]
 let p:Palette
 @State private var showDetails=true
 var body:some View {
  VStack(alignment:.leading,spacing:24){
   HStack(alignment:.firstTextBaseline){
    VStack(alignment:.leading,spacing:7){Text(w.tab=="AI纪要" ? "会议纪要":w.tab).font(.system(size:23,weight:.semibold));Text(subtitle).font(.callout).foregroundStyle(p.muted)}
    Spacer()
    if w.tab=="章节"{Toggle("显示摘要",isOn:$showDetails).toggleStyle(.checkbox).font(.callout)}
   }
   if nodes.isEmpty {Label(w.tab=="分歧点" ? "未发现明确分歧或待确认信息":"未发现原文明示的待办",systemImage:"checkmark.circle").foregroundStyle(p.muted).padding(.vertical,30)}
   ForEach(Array(nodes.enumerated()),id:\.offset){index,node in
    if w.tab=="思维链" {OpinionBranch(node:node,p:p,open:w.revealSource)}
    else if w.tab=="分歧点" {DisputeCard(node:node,p:p,open:w.revealSource)}
    else if w.tab=="待办" {task(node)}
    else if w.tab=="章节" {chapter(node,index:index)}
    else {minutes(node)}
   }
   Text("内容根据逐字稿整理。身份未识别时保留原标签；点击时间可核对原文。").font(.caption).foregroundStyle(p.muted).padding(.top,8)
  }.padding(.vertical,18).padding(.horizontal,12).frame(maxWidth:920,alignment:.leading).frame(maxWidth:.infinity)
 }
 private var subtitle:String {switch w.tab{case "思维链":return "按议题展开观点、理由、回应与结论";case "分歧点":return "区分意见冲突、执行条件和待确认信息";case "章节":return "按讨论顺序回顾，点击时间定位原文";case "待办":return "明确任务与建议跟进分别标注，完成状态保存在本机";default:return "讨论、决定与待确认事项分层呈现"}}
 private func minutes(_ n:AnalysisNode)->some View {
  VStack(alignment:.leading,spacing:14){
   Text(n.title).font(.system(size:17,weight:.semibold)).foregroundStyle(p.actionText)
   Text(n.body).font(.system(size:15)).lineSpacing(6).textSelection(.enabled)
   Evidence(node:n,p:p,open:w.revealSource)
   ForEach(Array((n.children ?? []).enumerated()),id:\.offset){_,child in
    VStack(alignment:.leading,spacing:9){NodeText(node:child,p:p,open:w.revealSource)}.padding(15).frame(maxWidth:.infinity,alignment:.leading).background(p.side.opacity(0.65)).clipShape(RoundedRectangle(cornerRadius:10))
   }
  }.padding(.bottom,12).frame(maxWidth:.infinity,alignment:.leading)
 }
 private func task(_ n:AnalysisNode)->some View {
  let done=(w.meeting.completedTasks ?? []).contains(n.id)
  return HStack(alignment:.top,spacing:14){
   Button{w.toggleTask(n.id)}label:{Image(systemName:done ? "checkmark.circle.fill":"circle").font(.system(size:23)).foregroundStyle(p.actionText).frame(width:32,height:32)}.buttonStyle(.plain).accessibilityLabel((done ? "标为未完成：":"完成任务：")+n.title).disabled(w.busy)
   VStack(alignment:.leading,spacing:12){
    HStack(alignment:.firstTextBaseline){Text(n.title).font(.system(size:16,weight:.semibold)).strikethrough(done);Spacer();Text(done ? "已完成":(n.kind ?? "待确认")).font(.caption).foregroundStyle(p.actionText)}
    Text(n.body).font(.system(size:14)).lineSpacing(5).textSelection(.enabled)
    HStack(spacing:20){Label(n.owner ?? "负责人待确认",systemImage:"person");Label(n.deadline ?? "期限待确认",systemImage:"calendar")}.font(.system(size:12)).foregroundStyle(p.muted)
    Evidence(node:n,p:p,open:w.revealSource)
   }.frame(maxWidth:.infinity,alignment:.leading)
  }.padding(18).background(p.side.opacity(done ? 0.35:0.7)).clipShape(RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(p.border,lineWidth:1))
 }
 private func chapter(_ n:AnalysisNode,index:Int)->some View {
  HStack(alignment:.top,spacing:20){
   Button{w.revealSource(n.times.first ?? 0)}label:{Text(Wire.time(n.times.first ?? 0)).font(.system(size:13,weight:.medium,design:.monospaced)).padding(.horizontal,10).padding(.vertical,7).foregroundStyle(p.actionText).background(p.hero).clipShape(Capsule())}.buttonStyle(.plain).accessibilityLabel("定位章节："+n.title)
   VStack(alignment:.leading,spacing:10){Text(n.title).font(.system(size:16,weight:.semibold));if showDetails{Text(n.body).font(.system(size:15)).lineSpacing(7).foregroundStyle(p.muted).textSelection(.enabled)}}.frame(maxWidth:.infinity,alignment:.leading)
  }.padding(.bottom,18).overlay(alignment:.bottom){p.border.frame(height:1)}
 }
}
struct Evidence:View {
 let node:AnalysisNode;let p:Palette;let open:(Double)->Void
 var body:some View {
  ViewThatFits(in:.horizontal){row;ScrollView(.horizontal,showsIndicators:false){row}}
 }
 private var row:some View {HStack(spacing:8){
  if let speaker=node.speaker {Label(speaker,systemImage:speaker.contains("区分") ? "person.crop.circle.badge.questionmark":"person.crop.circle").font(.system(size:12,weight:.medium)).foregroundStyle(p.actionText)}
  ForEach(Array(node.times.enumerated()),id:\.offset){_,time in Button{open(time)}label:{Label(Wire.time(time),systemImage:"play.circle").font(.system(size:12)).foregroundStyle(p.actionText).padding(.horizontal,7).padding(.vertical,4).background(p.accent.opacity(0.06)).clipShape(Capsule())}.buttonStyle(.plain).accessibilityLabel("查看原文 "+Wire.time(time))}
 }}
}
struct NodeText:View {
 let node:AnalysisNode;let p:Palette;let open:(Double)->Void
 var includeChildren=true
 var body:some View {VStack(alignment:.leading,spacing:9){Text(node.title).font(.system(size:15,weight:.semibold));Text(node.body).font(.system(size:14)).lineSpacing(6).textSelection(.enabled).fixedSize(horizontal:false,vertical:true);Evidence(node:node,p:p,open:open)
  if includeChildren {ForEach(Array((node.children ?? []).enumerated()),id:\.offset){_,child in AnyView(NodeText(node:child,p:p,open:open).padding(.leading,16).padding(.top,8))}}
 }}
}
struct OpinionBranch:View {
 let node:AnalysisNode;let p:Palette;let open:(Double)->Void
 @State private var expanded=true
 var body:some View {
  VStack(alignment:.leading,spacing:0){
   Button{expanded.toggle()}label:{HStack(spacing:10){Image(systemName:expanded ? "chevron.down":"chevron.right");Text(node.title).font(.system(size:17,weight:.semibold));Spacer();Text("\((node.children ?? []).count) 个观点").font(.caption)}.foregroundStyle(p.actionText).padding(.horizontal,17).padding(.vertical,14).background(p.hero).clipShape(RoundedRectangle(cornerRadius:12))}.buttonStyle(.plain).accessibilityLabel((expanded ? "收起":"展开")+node.title)
   if expanded {
    VStack(alignment:.leading,spacing:18){
     Text(node.body).font(.callout).foregroundStyle(p.muted).lineSpacing(5).padding(.leading,26)
     ForEach(Array((node.children ?? []).enumerated()),id:\.offset){_,viewpoint in
      HStack(alignment:.top,spacing:0){
       BranchConnector().stroke(p.accent.opacity(0.4),lineWidth:1.5).frame(width:26)
       VStack(alignment:.leading,spacing:14){
        NodeText(node:viewpoint,p:p,open:open,includeChildren:false)
        ForEach(Array((viewpoint.children ?? []).enumerated()),id:\.offset){_,detail in
         HStack(alignment:.top,spacing:10){Circle().fill(p.accent.opacity(0.6)).frame(width:6,height:6).padding(.top,6);NodeText(node:detail,p:p,open:open)}.padding(.leading,10)
        }
       }.padding(17).frame(maxWidth:.infinity,alignment:.leading).background(p.side.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(p.border,lineWidth:1))
      }.fixedSize(horizontal:false,vertical:true)
     }
    }.padding(.leading,18).padding(.top,16).overlay(alignment:.leading){p.accent.opacity(0.3).frame(width:1.5).padding(.leading,18)}
   }
  }.frame(maxWidth:.infinity,alignment:.leading)
 }
}
struct BranchConnector:Shape {
 func path(in rect:CGRect)->Path {var path=Path();path.move(to:CGPoint(x:0,y:0));path.addLine(to:CGPoint(x:0,y:18));path.addQuadCurve(to:CGPoint(x:12,y:30),control:CGPoint(x:0,y:30));path.addLine(to:CGPoint(x:rect.width,y:30));return path}
}
struct DisputeCard:View {
 let node:AnalysisNode;let p:Palette;let open:(Double)->Void
 var body:some View {
  VStack(alignment:.leading,spacing:16){
   HStack{Text(node.title).font(.system(size:17,weight:.semibold));Spacer();Text(node.kind ?? "待确认").font(.system(size:12,weight:.medium)).foregroundStyle(p.actionText).padding(7).background(p.hero).clipShape(Capsule())}
   if node.kind != "明确意见冲突" {Text("此项不表示人员对立").font(.caption).foregroundStyle(p.muted)}
   // 自适应双列立场，窗口较窄时自动堆叠。
   LazyVGrid(columns:(node.children ?? []).count>1 ? [GridItem(.flexible(minimum:180),spacing:14),GridItem(.flexible(minimum:180),spacing:14)]:[GridItem(.flexible(),spacing:14)],alignment:.leading,spacing:14){
    ForEach(Array((node.children ?? []).enumerated()),id:\.offset){_,position in NodeText(node:position,p:p,open:open).padding(16).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(p.side).clipShape(RoundedRectangle(cornerRadius:10))}
   }
   Divider();Text(node.body).font(.system(size:14)).lineSpacing(6).textSelection(.enabled);Evidence(node:node,p:p,open:open)
  }.padding(20).background(p.paper).clipShape(RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(p.border,lineWidth:1))
 }
}
