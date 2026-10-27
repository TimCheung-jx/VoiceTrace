import SwiftUI
import AppKit
struct Workbench:View {
 @ObservedObject var w:Workspace
 @Environment(\.accessibilityReduceMotion) private var reduceMotion
 @AppStorage("vt.motionEnabled") private var motionEnabled=true
 @AppStorage("vt.assistantVisible") private var assistantVisible=true
 @State private var timestamps=true
 @State private var search=""
 var p:Palette{Palette.named(w.theme)}
 var animation:Animation? {reduceMotion || !motionEnabled ? nil:.easeInOut(duration:0.2)}
 static let tabs=["转写","笔记","AI纪要","思维链","分歧点","章节","待办"]
 var body:some View {
  HStack(spacing:0){sidebar
   VStack(spacing:0){topbar
    VStack(alignment:.leading,spacing:23){heading;player
     HStack(alignment:.top,spacing:28){
      VStack(alignment:.leading,spacing:0){tabbar;actions;DocumentPane(w:w,p:p).frame(maxWidth:.infinity,maxHeight:.infinity);footer}.frame(minWidth:450,maxWidth:.infinity)
      if assistantVisible{AssistantPane(w:w,p:p,close:{withAnimation(animation){assistantVisible=false}}).frame(width:264).transition(.move(edge:.trailing).combined(with:.opacity))}
     }.frame(maxHeight:.infinity)
    }.padding(.horizontal,30).padding(.top,26).padding(.bottom,12)
   }.background(p.paper)
  }.foregroundStyle(p.ink).tint(p.accent).frame(minWidth:assistantVisible ? 1110:880,minHeight:720)
   .animation(animation,value:assistantVisible)
   .sheet(isPresented:$w.settings){ConfigurationView(w:w).tint(p.accent)}
   .alert("声迹提示",isPresented:Binding(get:{!w.alert.isEmpty},set:{if !$0{w.alert=""}})){Button("确定"){w.alert=""}} message:{Text(w.alert)}
 }
 private var sidebar:some View {
  VStack(alignment:.leading,spacing:23){
   HStack(spacing:9){Image(nsImage:NSImage(contentsOf:Bundle.main.url(forResource:"VoiceTrace",withExtension:"png") ?? URL(fileURLWithPath:"")) ?? NSImage()).resizable().scaledToFit().frame(width:43,height:43).accessibilityHidden(true)
    VStack(alignment:.leading,spacing:1){Text("声迹").font(.system(size:23,weight:.semibold));Text("VoiceTrace").font(.system(size:11)).foregroundStyle(.secondary)}
   }.padding(.horizontal,6)
   Button{w.newMeeting()}label:{Label("新建录音",systemImage:"plus").frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(QuietButton(tint:p.ink)).background(.white).clipShape(RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).strokeBorder(p.ink.opacity(0.08))).disabled(w.locked)
   HStack{Image(systemName:"square.grid.2x2");Text("全部会议");Spacer();Text("\(w.history.count)").font(.caption)}.font(.system(size:13,weight:.medium)).padding(12).foregroundStyle(p.accent).background(p.accent.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius:8))
   TextField("搜索会议",text:$search).textFieldStyle(.roundedBorder).font(.callout).accessibilityLabel("搜索本地会议")
   Text("最近会议").font(.system(size:11)).foregroundStyle(.secondary).padding(.horizontal,10)
   ScrollView{LazyVStack(spacing:6){
    ForEach(w.history.filter{search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)}){m in
     Button{w.load(m)}label:{VStack(alignment:.leading,spacing:7){Text(m.title).font(.system(size:13)).lineLimit(2);HStack{Text(m.created,style:.date);Text("·");Text(m.sentences.isEmpty ? "尚无转写":"\(m.sentences.count)段文字")}.font(.system(size:10)).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading).padding(11).background(w.meeting.id==m.id ? Color.white:Color.clear).clipShape(RoundedRectangle(cornerRadius:8))}.buttonStyle(.plain).disabled(w.locked)
    }
    if w.history.isEmpty {Text("会议将保存在这台Mac上").font(.caption).foregroundStyle(.secondary).padding(.vertical,18)}
   }}
   Spacer(minLength:0)
   Button{w.settingsPage="外观";w.settings=true}label:{HStack{Label("设置",systemImage:"gearshape");Spacer();Text("⌘ ,").font(.caption)}}.buttonStyle(QuietButton(tint:p.ink))
   Button{w.persist();NSWorkspace.shared.open(w.root)}label:{Label("本机会议资料",systemImage:"folder")}.font(.system(size:11)).foregroundStyle(.secondary).buttonStyle(.plain).padding(.horizontal,12)
   Text("VoiceTrace · Mac 0.6.1").font(.system(size:10)).foregroundStyle(.secondary).padding(.horizontal,12)
  }.padding(.horizontal,16).padding(.top,26).padding(.bottom,18).frame(width:214).background(p.side)
 }
 private var topbar:some View {
  HStack{HStack(spacing:12){Text("工作台");Image(systemName:"chevron.right").font(.system(size:9));Text("会议详情")}.font(.system(size:12)).foregroundStyle(.secondary)
   Spacer()
   Button{withAnimation(animation){assistantVisible.toggle()}}label:{Label("AI助手",systemImage:"sidebar.right")}.buttonStyle(QuietButton(tint:p.ink)).accessibilityLabel(assistantVisible ? "收起AI助手":"打开AI助手")
  }.padding(.horizontal,28).frame(height:54).overlay(alignment:.bottom){p.ink.opacity(0.08).frame(height:1)}
 }
 private var heading:some View {
  HStack(spacing:20){VStack(alignment:.leading,spacing:9){
   Text("会议工作台").font(.system(size:10,weight:.medium)).tracking(1).foregroundStyle(.secondary)
   TextField("为会议命名",text:$w.meeting.title).textFieldStyle(.plain).font(.system(size:26,weight:.semibold)).onSubmit{w.persist()}.accessibilityLabel("会议名称")
   HStack(spacing:10){Text(w.meeting.created,style:.date);Text("·");Text("普通话");Text("·");Text(w.phase=="录音中" ? "实时转写中":w.meeting.summary.isEmpty ? "尚未整理":"已整理")}.font(.system(size:11)).foregroundStyle(.secondary)
  }
   Spacer(minLength:12)
   recordControls
  }
 }
 @ViewBuilder private var recordControls:some View {
  if w.phase=="录音中" {
   HStack(spacing:6){Button("暂停"){w.stop(pause:true)}.buttonStyle(QuietButton(tint:p.accent));Button{w.stop()}label:{Label("结束录音",systemImage:"stop.fill")}.buttonStyle(QuietButton(prominent:true,tint:p.accent))}
  }else if w.phase=="连接中" || w.phase=="结束中" {
   HStack{ProgressView().controlSize(.small);Text(w.phase).font(.callout);if w.phase=="连接中"{Button("取消"){w.cancelConnecting()}.buttonStyle(.borderless)}}
  }else {
   Button{Task{await w.start()}}label:{Label(w.meeting.recordings.isEmpty ? "开始录音":"继续录音",systemImage:"circle.fill")}.buttonStyle(QuietButton(prominent:true,tint:p.accent)).disabled(w.processing)
  }
 }
 private var player:some View {
  VStack(alignment:.leading,spacing:8){
   HStack(spacing:18){
    Button{w.togglePlayback()}label:{Image(systemName:w.playing ? "pause.fill":"play.fill").font(.system(size:14)).foregroundStyle(p.accent).frame(width:38,height:38).background(p.accent.opacity(0.08)).clipShape(Circle())}.buttonStyle(.plain).disabled(w.totalDuration==0 || w.phase != "空闲").accessibilityLabel(w.playing ? "暂停回听":"播放录音")
    VStack(spacing:5){
     if w.phase=="录音中" {LiveMeter(active:motionEnabled && !reduceMotion,color:p.accent).frame(height:23).accessibilityLabel("正在录音")}
     else{Slider(value:Binding(get:{min(w.playbackPosition,max(w.totalDuration,1))},set:{w.seek($0)}),in:0...max(w.totalDuration,1)).controlSize(.small).disabled(w.totalDuration==0).accessibilityLabel("录音回听位置")}
     HStack{TimelineView(.periodic(from:.now,by:1)){_ in Text(Wire.time(w.phase=="录音中" ? w.elapsed:w.playbackPosition))};Spacer();Text(Wire.time(w.totalDuration))}.font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
    }
    if !w.meeting.sentences.isEmpty{Text("\(Set(w.meeting.sentences.map{$0.speaker}).count)类发言标签").font(.system(size:10)).foregroundStyle(.secondary).help("实时标签待会后识别；不同录音段可能属于同一人")}
    Button{w.addMark()}label:{Label("标记",systemImage:"bookmark")}.buttonStyle(QuietButton(tint:p.ink))
   }
   if w.phase != "空闲"{Text(w.status).font(.system(size:11)).foregroundStyle(.secondary)}
  }.padding(.horizontal,18).padding(.vertical,13).background(.white).clipShape(RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).strokeBorder(p.ink.opacity(0.1)))
 }
 private var tabbar:some View {
  ScrollView(.horizontal,showsIndicators:false){HStack(spacing:19){ForEach(Self.tabs,id:\.self){t in
   Button{withAnimation(animation){w.tab=t}}label:{VStack(spacing:12){Text(t).font(.system(size:13,weight:w.tab==t ? .semibold:.regular)).foregroundStyle(w.tab==t ? p.accent:p.ink.opacity(0.65));Rectangle().fill(w.tab==t ? p.accent:Color.clear).frame(height:2)}}.buttonStyle(.plain).accessibilityLabel(t+(w.tab==t ? "，已选中":""))
  }}}.frame(height:37).overlay(alignment:.bottom){p.ink.opacity(0.1).frame(height:1)}
 }
 private var actions:some View {
  HStack(spacing:4){Text(w.tab=="分歧点" ? "以原文为依据，区分冲突与待确认。":"内容可复制、导出与分享。").font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1);Spacer(minLength:4)
   Button{w.copySection(timestamps:timestamps)}label:{Label("复制",systemImage:"doc.on.doc")}.buttonStyle(QuietButton(tint:p.ink)).disabled(w.sectionSnapshot.body.isEmpty)
   Menu{Toggle("保留时间标记",isOn:$timestamps);Divider();ForEach(DownloadFormat.allCases.filter{$0 != .png || w.tab=="思维链"},id:\.self){format in Button(format.rawValue){w.downloadSection(format,timestamps:timestamps)}};Divider();Button("整场会议 Markdown"){w.export()}}label:{Label("导出",systemImage:"square.and.arrow.down")}.menuStyle(.borderlessButton).fixedSize().font(.system(size:12))
   SharePopover(w:w,timestamps:timestamps,p:p)
  }.padding(.vertical,12)
 }
 private var footer:some View {
  HStack(spacing:8){Circle().fill(p.accent).frame(width:5,height:5);Text(w.status).lineLimit(2);Spacer();Text("本机保存 · 云端处理")}.font(.system(size:10)).foregroundStyle(.secondary).padding(.top,10).overlay(alignment:.top){p.ink.opacity(0.07).frame(height:1)}
 }
}
struct LiveMeter:View {
 let active:Bool
 let color:Color
 var body:some View {
  TimelineView(.animation(minimumInterval:0.1,paused:!active)){context in
   let t=active ? context.date.timeIntervalSinceReferenceDate:0
   GeometryReader{geometry in HStack(alignment:.center,spacing:4){ForEach(0..<min(90,max(10,Int(geometry.size.width/7))),id:\.self){i in
    RoundedRectangle(cornerRadius:2).fill(color.opacity(0.7)).frame(width:3,height:active ? 5+abs(sin(t*3+Double(i)*0.8))*15:9)
   }}.frame(height:23)}
  }.help("录音状态动效，不代表真实音量或音频波形")
 }
}
struct SharePopover:View {
 @ObservedObject var w:Workspace
 let timestamps:Bool
 let p:Palette
 @State private var shown=false
 var body:some View {
  Button{shown.toggle()}label:{Label("分享",systemImage:"square.and.arrow.up")}.buttonStyle(QuietButton(tint:p.ink)).popover(isPresented:$shown){
   VStack(alignment:.leading,spacing:12){Text("分享当前页面").font(.headline)
    NativeShareButton(title:"系统分享文字",items:{w.shareItems(file:false,timestamps:timestamps)})
    NativeShareButton(title:"系统分享PDF",items:{w.shareItems(file:true,timestamps:timestamps)})
    Divider();Button("显示PDF文件，拖入微信或钉钉"){w.revealShareFile(timestamps:timestamps);shown=false}.buttonStyle(.borderless)
    Text("系统分享菜单中可用的应用由macOS决定。选择接收人后由您确认发送。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
   }.padding(18).frame(width:275)
  }.disabled(w.sectionSnapshot.body.isEmpty)
 }
}
