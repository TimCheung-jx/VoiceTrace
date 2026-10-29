import SwiftUI
import AppKit
struct Workbench:View {
 @ObservedObject var w:Workspace
 @Environment(\.accessibilityReduceMotion) private var reduceMotion
 @AppStorage("vt.motionEnabled") private var motionEnabled=true
 @AppStorage("vt.assistantVisible") private var assistantVisible=true
 @State private var width:CGFloat=1280
 @State private var assistantSheet=false
 @State private var timestamps=true
 @State private var editing=false
 @State private var historyShown=false
 @State private var suggestionShown=false
 @State private var segmentsShown=false
 @State private var search=""
 @State private var deleteIDs=Set<String>()
 var p:Palette{Palette.named(w.theme)}
 var inlineAssistant:Bool{assistantVisible && width>=1180}
 var animation:Animation?{reduceMotion || !motionEnabled ? nil:.easeInOut(duration:0.18)}
 static let tabs=["转写","笔记","AI纪要","思维链","分歧点","章节","待办"]
 var body:some View{
  GeometryReader{geometry in
   HStack(spacing:0){sidebar;VStack(spacing:0){topbar;if w.allMeetings{library}else{detail}}.background(p.paper)}
    .onAppear{width=geometry.size.width}.onChange(of:geometry.size.width){width=$0}
  }.foregroundStyle(p.ink).tint(p.accent).frame(minWidth:960,minHeight:640)
   .animation(animation,value:inlineAssistant)
   .sheet(isPresented:$editing){SectionEditor(w:w,section:w.tab).tint(p.accent)}
   .sheet(isPresented:$historyShown){RevisionView(w:w).tint(p.accent)}
   .sheet(isPresented:$suggestionShown){SuggestionView(w:w,section:w.tab).tint(p.accent)}
   .sheet(isPresented:$segmentsShown){SegmentView(w:w).tint(p.accent)}
   .sheet(isPresented:$w.showRecovery){RecoveryView(w:w).tint(p.accent)}
   .sheet(isPresented:$w.settings){ConfigurationView(w:w).tint(p.accent)}
   .sheet(isPresented:$assistantSheet){AssistantPane(w:w,p:p,close:{assistantSheet=false}).padding(24).frame(width:420,height:640).background(p.paper)}
   .confirmationDialog("删除会议？文字及录音会移入最近删除，可恢复。",isPresented:Binding(get:{!deleteIDs.isEmpty},set:{if !$0{deleteIDs=[]}})){Button("移入最近删除",role:.destructive){w.moveToTrash(deleteIDs);deleteIDs=[]}}
   .alert("声迹提示",isPresented:Binding(get:{!w.alert.isEmpty},set:{if !$0{w.alert=""}})){Button("确定"){w.alert=""}}message:{Text(w.alert)}
 }
 private var detail:some View{
  VStack(alignment:.leading,spacing:16){heading;player
   HStack(alignment:.top,spacing:24){
    VStack(alignment:.leading,spacing:0){tabbar;actions;DocumentPane(w:w,p:p).frame(maxWidth:.infinity,maxHeight:.infinity);footer}.frame(minWidth:440,maxWidth:.infinity)
    if inlineAssistant{AssistantPane(w:w,p:p,close:{withAnimation(animation){assistantVisible=false}}).frame(width:252).transition(.opacity)}
   }.frame(maxHeight:.infinity)
  }.padding(.horizontal,UIGrid.gutter).padding(.top,20).padding(.bottom,12)
 }
 private var library:some View{
  VStack(spacing:16){if w.phase != "空闲" || w.paused{HStack{VStack(alignment:.leading,spacing:4){Text(w.meeting.title).font(.headline).lineLimit(1);Text(w.meetingState).font(.caption).foregroundStyle(p.muted)};Spacer();Button("返回会议"){w.allMeetings=false}.buttonStyle(QuietButton(tint:p.ink));recordControls}.padding(14).background(p.surface).clipShape(RoundedRectangle(cornerRadius:UIGrid.panel)).overlay(RoundedRectangle(cornerRadius:UIGrid.panel).strokeBorder(p.border))};MeetingLibrary(w:w)}.padding(UIGrid.gutter)
 }
 private var topbar:some View{
  HStack(spacing:10){Text(w.allMeetings ? "会议资料":"会议工作台").font(.system(size:13,weight:.medium));Spacer();Label(w.saveFailed ? "保存失败":w.saving ? "保存中":"本机保存",systemImage:w.saveFailed ? "exclamationmark.circle":"externaldrive").font(.system(size:12)).foregroundStyle(w.saveFailed ? p.danger:p.muted)
   Button{if width<1180{assistantSheet=true}else{withAnimation(animation){assistantVisible.toggle()}}}label:{Label("会议助手",systemImage:"sidebar.right")}.buttonStyle(QuietButton(tint:p.ink)).accessibilityLabel(inlineAssistant ? "收起会议助手":"打开会议助手")
  }.padding(.horizontal,UIGrid.gutter).frame(height:48).overlay(alignment:.bottom){p.border.frame(height:0.5)}
 }
 private var heading:some View{
  HStack(alignment:.center,spacing:20){VStack(alignment:.leading,spacing:8){TextField("会议名称",text:$w.meeting.title).textFieldStyle(.plain).font(.system(size:25,weight:.semibold)).onSubmit{w.persist()}.accessibilityLabel("会议名称");HStack(spacing:12){Text(w.meeting.created,style:.date);Label("普通话",systemImage:"globe");Text(w.meetingState)}.font(.system(size:12)).foregroundStyle(p.muted)};Spacer(minLength:4);recordControls}
 }
 @ViewBuilder private var recordControls:some View{
  if w.phase=="录音中"{HStack(spacing:8){Button{w.stop(pause:true)}label:{Label("暂停",systemImage:"pause")}.buttonStyle(QuietButton(tint:p.ink,outlined:true));Button{w.stop()}label:{Label("结束录音",systemImage:"stop.fill")}.buttonStyle(QuietButton(prominent:true,tint:p.accent))}}
  else if w.phase=="连接中" || w.phase=="结束中"{HStack(spacing:10){ProgressView().controlSize(.small);Text(w.phase=="连接中" ? "连接语音服务…":"保存最后一句…").font(.callout);if w.phase=="连接中"{Button("取消"){w.cancelConnecting()}.buttonStyle(QuietButton(tint:p.ink))}}}
  else{HStack(spacing:8){if w.paused{Button("结束录音"){w.stop()}.buttonStyle(QuietButton(tint:p.ink,outlined:true))};Button{Task{await w.start()}}label:{Label(w.paused ? "继续录音":w.meeting.recordings.isEmpty ? "开始录音":"追加录音",systemImage:w.paused ? "play.fill":"mic.fill")}.buttonStyle(QuietButton(prominent:true,tint:p.accent)).disabled(w.processing || w.liveBusy || w.saveFailed)}}
 }
 private var player:some View{
  VStack(alignment:.leading,spacing:12){HStack(spacing:14){
   Button{w.togglePlayback()}label:{Image(systemName:w.playing ? "pause.fill":"play.fill").frame(width:34,height:34).background(p.accent.opacity(0.08)).clipShape(Circle())}.foregroundStyle(p.actionText).buttonStyle(.plain).disabled(w.totalDuration==0 || w.phase != "空闲").accessibilityLabel(w.playing ? "暂停回听":"播放录音")
   if w.phase=="录音中"{ProgressView(value:Double(w.inputLevel),total:1).tint(p.accent).accessibilityLabel("麦克风实际输入音量")}else{Slider(value:Binding(get:{min(w.playbackPosition,max(w.totalDuration,1))},set:{w.seek($0)}),in:0...max(w.totalDuration,1)).controlSize(.small).disabled(w.totalDuration==0).accessibilityLabel("回听位置")}
   TimelineView(.periodic(from:.now,by:1)){_ in Text(Wire.time(w.phase=="录音中" ? w.elapsed:w.playbackPosition)+" / "+Wire.time(w.totalDuration)).font(.system(size:12,design:.monospaced)).foregroundStyle(p.muted)}
   Button{w.addMark()}label:{Label("标记",systemImage:"bookmark")}.buttonStyle(QuietButton(tint:p.ink))
  }
  HStack(spacing:10){StatusBadge(text:w.phase=="录音中" ? "实时转写中":"语音 · "+w.modelSettings.activeSpeech.name,symbol:"waveform",tint:p.actionText);Text("AI · "+w.aiState).font(.system(size:12)).foregroundStyle(p.muted).lineLimit(1);if w.liveBusy{ProgressView().controlSize(.mini)};Spacer(minLength:0);if let time=w.meeting.summaryThrough{Text("整理至 "+Wire.time(time)).font(.system(size:12)).foregroundStyle(p.muted)}}
  if w.saveFailed{HStack{Label("未能保存，请先重试或导出",systemImage:"exclamationmark.triangle").foregroundStyle(p.danger);Spacer();Button("重试"){w.persist()};Button("导出备份"){w.export()}}.font(.callout)}
  }.padding(14).background(p.surface).clipShape(RoundedRectangle(cornerRadius:UIGrid.panel)).overlay(RoundedRectangle(cornerRadius:UIGrid.panel).strokeBorder(p.border,lineWidth:0.7))
 }
 private var tabbar:some View{
  ScrollView(.horizontal,showsIndicators:false){HStack(spacing:20){ForEach(Self.tabs,id:\.self){tab in Button{withAnimation(animation){w.tab=tab}}label:{VStack(spacing:12){Text(tab).font(.system(size:13,weight:w.tab==tab ? .semibold:.regular)).foregroundStyle(w.tab==tab ? p.actionText:p.muted);Rectangle().fill(w.tab==tab ? p.accent:.clear).frame(height:2)}}.buttonStyle(.plain).accessibilityLabel(tab+(w.tab==tab ? "，已选中":""))}}}.frame(height:36).overlay(alignment:.bottom){p.border.frame(height:0.5)}
 }
 private var actions:some View{
  HStack(spacing:10){Button{w.requestLive(final:w.phase=="空闲" && !w.paused)}label:{Label(w.liveBusy ? "整理中":"更新整理",systemImage:"sparkles")}.buttonStyle(QuietButton(tint:p.actionText)).disabled(w.liveBusy || w.processing || w.transcript.isEmpty)
   Menu{if Workspace.sectionKeys[w.tab] != nil{Button("编辑并保护此页"){editing=true}.disabled(w.busy);Button("比较AI新建议"){suggestionShown=true}.disabled(w.meeting.aiSuggestion==nil)};Button("修订历史"){historyShown=true};Button("分段整理"){segmentsShown=true}.disabled((w.meeting.segmentSummaries ?? []).isEmpty)}label:{Label("编辑",systemImage:"pencil")}.menuStyle(.borderlessButton).fixedSize().font(.system(size:13))
   if (w.meeting.protectedSections ?? []).contains(w.tab){Image(systemName:"lock.shield").foregroundStyle(p.actionText).help("人工修订保护，AI不会覆盖")}
   Spacer(minLength:4)
   Button{w.copySection(timestamps:timestamps)}label:{Label("复制",systemImage:"doc.on.doc")}.buttonStyle(QuietButton(tint:p.ink)).disabled(w.sectionSnapshot.body.isEmpty)
   Menu{Toggle("保留时间标记",isOn:$timestamps);Divider();ForEach(DownloadFormat.allCases.filter{$0 != .png || w.tab=="思维链"},id:\.self){format in Button(format.rawValue){w.downloadSection(format,timestamps:timestamps)}};Divider();Button("整场会议 Markdown"){w.export()}}label:{Label("导出",systemImage:"square.and.arrow.down")}.menuStyle(.borderlessButton).fixedSize().font(.system(size:13))
   SharePopover(w:w,timestamps:timestamps,p:p)
  }.padding(.vertical,8)
 }
 private var footer:some View{HStack{Text(w.status).lineLimit(1);Spacer();if w.summaryDraft{Text("实时草稿 · 请核对")}}.font(.system(size:12)).foregroundStyle(p.muted).padding(.top,10).overlay(alignment:.top){p.border.frame(height:0.5)}}
 private var sidebar:some View{
  VStack(alignment:.leading,spacing:18){HStack(spacing:10){Image(nsImage:NSImage(contentsOf:Bundle.main.url(forResource:"VoiceTrace",withExtension:"png") ?? URL(fileURLWithPath:"")) ?? NSImage()).resizable().scaledToFit().frame(width:38,height:38).accessibilityHidden(true);VStack(alignment:.leading,spacing:2){Text("声迹").font(.system(size:22,weight:.semibold));Text("VoiceTrace").font(.system(size:12)).foregroundStyle(p.muted)}}.padding(.horizontal,6).padding(.bottom,4)
   Button{w.newMeeting()}label:{Label("新建会议",systemImage:"plus").frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(QuietButton(tint:p.actionText,outlined:true)).disabled(w.busy)
   Button{w.allMeetings=true;w.refresh()}label:{HStack{Label("全部会议",systemImage:"square.grid.2x2");Spacer();Text("\(w.history.count)").font(.system(size:12))}.font(.system(size:13,weight:.medium)).padding(10).background(w.allMeetings ? p.accent.opacity(0.08):.clear).clipShape(RoundedRectangle(cornerRadius:8))}.buttonStyle(.plain).foregroundStyle(w.allMeetings ? p.actionText:p.ink)
   TextField("搜索会议",text:$search).textFieldStyle(.roundedBorder).font(.system(size:13)).accessibilityLabel("搜索本地会议")
   Text("最近会议").font(.system(size:12,weight:.medium)).foregroundStyle(p.muted).padding(.horizontal,8)
   ScrollView{LazyVStack(spacing:5){ForEach(w.history.filter{search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)}){item in
    Button{w.load(item)}label:{SidebarMeetingRow(item:item,selected:!w.allMeetings && w.meeting.id==item.id,p:p)}.buttonStyle(.plain).disabled(w.busy).contextMenu{Button("重命名"){rename(item)};Button("删除",role:.destructive){deleteIDs=[item.id]}}
   };if w.history.isEmpty{Text("新建会议后，记录将显示在这里。").font(.system(size:12)).foregroundStyle(p.muted).padding(10)}}}
   Spacer(minLength:0)
   Button{w.settingsPage="外观";w.settings=true}label:{HStack{Label("设置",systemImage:"gearshape");Spacer();Text("⌘ ,").font(.system(size:12))}}.buttonStyle(QuietButton(tint:p.ink))
   Button{w.persist();NSWorkspace.shared.open(w.root)}label:{Label("本机资料",systemImage:"folder")}.buttonStyle(QuietButton(tint:p.muted))
   Text(AppIdentity.personal ? "个人版 0.10.0":"VoiceTrace 0.10.0").font(.system(size:12)).foregroundStyle(p.muted).padding(.horizontal,12)
  }.padding(.horizontal,14).padding(.top,22).padding(.bottom,16).frame(width:212).background(p.side).overlay(alignment:.trailing){p.border.frame(width:0.5)}
 }
 private func rename(_ item:Meeting){let panel=NSAlert();panel.messageText="重命名会议";let field=NSTextField(string:item.title);field.frame=NSRect(x:0,y:0,width:320,height:26);panel.accessoryView=field;panel.addButton(withTitle:"保存");panel.addButton(withTitle:"取消");if panel.runModal() == .alertFirstButtonReturn{w.renameMeeting(item,title:field.stringValue)}}
}
private struct SidebarMeetingRow:View{
 let item:Meeting;let selected:Bool;let p:Palette
 var body:some View{VStack(alignment:.leading,spacing:7){Text(item.title).font(.system(size:13,weight:selected ? .medium:.regular)).lineLimit(2);Text(item.created,style:.date).font(.system(size:12)).foregroundStyle(p.muted)}.frame(maxWidth:.infinity,alignment:.leading).padding(11).background(selected ? p.accent.opacity(0.075):.clear).clipShape(RoundedRectangle(cornerRadius:8)).foregroundStyle(selected ? p.actionText:p.ink)}
}
struct SharePopover:View {
 @ObservedObject var w:Workspace
 let timestamps:Bool
 let p:Palette
 @State private var shown=false
 var body:some View{Button{shown.toggle()}label:{Label("分享",systemImage:"square.and.arrow.up")}.buttonStyle(QuietButton(tint:p.ink)).popover(isPresented:$shown){VStack(alignment:.leading,spacing:14){Text("分享当前页面").font(.headline);NativeShareButton(title:"系统分享文字",items:{w.shareItems(file:false,timestamps:timestamps)});NativeShareButton(title:"系统分享PDF",items:{w.shareItems(file:true,timestamps:timestamps)});Divider();Button("显示PDF，拖入微信或钉钉"){w.revealShareFile(timestamps:timestamps);shown=false}.buttonStyle(.borderless);Text("接收人由您选择并确认发送。").font(.caption).foregroundStyle(.secondary)}.padding(20).frame(width:290)}.disabled(w.sectionSnapshot.body.isEmpty)}
}
