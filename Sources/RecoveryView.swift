import SwiftUI
struct RecoveryView:View {
 @ObservedObject var w:Workspace
 var body:some View{
  VStack(alignment:.leading,spacing:18){
   Text("发现可恢复录音").font(.title2.bold())
   Text("这些录音尚未登记到会议，可能来自异常退出。恢复在本机完成，保留原件，不自动上传。恢复后需补转写并核对内容。").font(.callout)
   List(w.recoveryItems){item in HStack{VStack(alignment:.leading){Text(item.title);Text("录音约 "+Wire.time(item.duration)+" · 从 "+Wire.time(item.offset)+" 开始").font(.caption).foregroundStyle(.secondary)};Spacer();Button("恢复"){w.recoverAudio(item)}.disabled(w.busy)}}
   HStack{Text(w.recoveryItems.isEmpty ? "已无待恢复录音":"也可稍后在设置→录音与整理中恢复").font(.caption).foregroundStyle(.secondary);Spacer();Button("完成"){w.showRecovery=false}}
  }.padding(24).frame(width:650,height:420)
 }
}
