import SwiftUI
struct MeetingLibrary:View{
 @ObservedObject var w:Workspace
 @State private var selection=Set<String>()
 @State private var query=""
 @State private var deleted=false
 @State private var confirm=false
 var p:Palette{Palette.named(w.theme)}
 var items:[Meeting]{(deleted ? w.trash:w.history).filter{query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)}}
 var body:some View{
  VStack(alignment:.leading,spacing:18){
   HStack(alignment:.firstTextBaseline){VStack(alignment:.leading,spacing:6){Text(deleted ? "最近删除":"全部会议").font(.system(size:25,weight:.semibold));Text(deleted ? "恢复记录，或确认后永久删除。":"\(w.history.count) 场会议，保存在这台 Mac 上。").font(.system(size:13)).foregroundStyle(p.muted)};Spacer();Picker("会议范围",selection:$deleted){Text("全部会议").tag(false);Text("最近删除").tag(true)}.pickerStyle(.segmented).frame(width:210).onChange(of:deleted){_ in selection=[]}}
   HStack{Image(systemName:"magnifyingglass").foregroundStyle(p.muted);TextField("搜索会议名称",text:$query).textFieldStyle(.plain).accessibilityLabel("搜索会议名称");if !query.isEmpty{Button{query=""}label:{Image(systemName:"xmark.circle.fill")}.buttonStyle(.plain).accessibilityLabel("清空搜索")}}.padding(11).background(p.surface).clipShape(RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).strokeBorder(p.border))
   if items.isEmpty{empty}else{table}
   HStack(spacing:12){Text("已选 \(selection.count) 项").font(.system(size:13,weight:.medium));Button("全选"){selection=Set(items.map{$0.id})}.buttonStyle(QuietButton(tint:p.ink)).disabled(items.isEmpty);if !selection.isEmpty{Button("取消选择"){selection=[]}.buttonStyle(QuietButton(tint:p.muted))};Spacer();if deleted{Button("恢复所选"){w.restoreMeetings(selection);selection=selection.intersection(Set(w.trash.map{$0.id}))}.buttonStyle(QuietButton(tint:p.actionText,outlined:true)).disabled(selection.isEmpty || w.busy)};Button{confirm=true}label:{Label(deleted ? "永久删除":"移入最近删除",systemImage:"trash")}.buttonStyle(QuietButton(tint:p.danger,outlined:true)).disabled(selection.isEmpty || w.busy)}
   Text(deleted ? "永久删除无法恢复。恢复和删除结果会单独报告。":"勾选记录或按住 Command 多选，Shift 连选。删除的文字及录音可在最近删除中恢复。").font(.system(size:12)).foregroundStyle(p.muted)
  }.confirmationDialog(deleted ? "永久删除所选 \(selection.count) 场会议及录音？此操作不可恢复。":"将所选 \(selection.count) 场会议及录音移入最近删除？",isPresented:$confirm){Button(deleted ? "永久删除":"移入最近删除",role:.destructive){if deleted{w.permanentlyDelete(selection)}else{w.moveToTrash(selection)};selection=selection.intersection(Set(items.map{$0.id}))}}
 }
 private var table:some View{
  Table(items,selection:$selection){
   TableColumn("选择"){item in Toggle("选择"+item.title,isOn:Binding(get:{selection.contains(item.id)},set:{if $0{selection.insert(item.id)}else{selection.remove(item.id)}})).toggleStyle(.checkbox).labelsHidden()}.width(36)
   TableColumn("会议"){item in VStack(alignment:.leading,spacing:5){Text(item.title).font(.system(size:14,weight:.medium)).lineLimit(2);Text("\(item.sentences.count) 段文字 · "+Wire.time(item.recordings.reduce(0){$0+$1.duration})).font(.system(size:12)).foregroundStyle(p.muted)}.padding(.vertical,8)}.width(min:190,ideal:320)
   TableColumn("日期"){item in Text(item.created,format:.dateTime.month().day()).font(.system(size:13)).foregroundStyle(p.muted)}.width(80)
   TableColumn("状态"){item in Text(item.captureState ?? (item.summary.isEmpty ? "未整理":"已有整理")).font(.system(size:12)).foregroundStyle(p.muted)}.width(84)
   TableColumn(""){item in Button(deleted ? "恢复":"打开"){if deleted{w.restoreMeeting(item)}else{w.load(item)}}.buttonStyle(QuietButton(tint:p.actionText)).disabled(w.busy)}.width(56)
  }.clipShape(RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).strokeBorder(p.border,lineWidth:0.7))
 }
 private var empty:some View{VStack(spacing:14){Image(systemName:deleted ? "trash":"folder").font(.system(size:30,weight:.light)).foregroundStyle(p.actionText);Text(query.isEmpty ? (deleted ? "最近删除为空":"还没有会议记录"):"未找到匹配的会议").font(.system(size:19,weight:.medium));Text(query.isEmpty ? (deleted ? "删除的会议会先保留在这里。":"点击新建会议，开始录音或记笔记。"):"试试其他名称，或清空搜索。").font(.system(size:13)).foregroundStyle(p.muted);if !query.isEmpty{Button("清空搜索"){query=""}.buttonStyle(QuietButton(tint:p.actionText))}}.frame(maxWidth:.infinity,maxHeight:.infinity)}
}
