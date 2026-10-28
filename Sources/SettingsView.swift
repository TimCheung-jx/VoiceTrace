import SwiftUI
import AppKit
struct ConfigurationView:View {
 @ObservedObject var w:Workspace
 @State private var speech=SpeechProfile()
 @State private var text=TextProfile()
 @State private var ali=""
 @State private var deep=""
 @State private var testing=false
 @State private var feedback=""
 private var p:Palette{Palette.named(w.theme)}
 @FocusState private var focused:String?
 private var unavailable:Bool {w.busy || testing}
 var body:some View {
  VStack(alignment:.leading,spacing:16){
   DialogTitle(title:"设置",subtitle:"外观、录音行为和模型服务。密钥存于本机钥匙串，留空不会清除。")
   if w.busy {Text("当前任务进行中，可查看设置；结束后可保存、切换或测试。").foregroundStyle(.orange)}
   Picker("设置分类",selection:$w.settingsPage){Text("外观").tag("外观");Text("录音与整理").tag("录音与整理");Text("模型与服务").tag("模型与服务")}.pickerStyle(.segmented)
   ScrollView {
    if w.settingsPage=="外观" {appearanceSection}else if w.settingsPage=="录音与整理" {recordingSection}else{HStack(alignment:.top,spacing:24){speechSection;paddingDivider;textSection}}
   }
   Divider()
   HStack {if testing{ProgressView().controlSize(.small)};Text(feedback).font(.callout).textSelection(.enabled);Spacer();if w.settingsPage=="模型与服务"{Button("保存语音配置"){saveSpeech()}.buttonStyle(QuietButton(tint:p.actionText,outlined:true)).disabled(unavailable);Button("保存整理配置"){saveText()}.buttonStyle(QuietButton(tint:p.actionText,outlined:true)).disabled(unavailable)};Button("完成"){w.settings=false}.buttonStyle(QuietButton(prominent:true,tint:p.accent)).keyboardShortcut(.defaultAction).disabled(testing)}
   Text("语音测试只建立实时任务，不采集麦克风；整理测试只发送固定虚构文字。测试可能产生服务费用。会后识别模型仍需用短录音验证。").font(.caption).foregroundStyle(p.muted)
  }.padding(24).frame(width:860,height:720).background(p.paper).foregroundStyle(p.ink)
  .onAppear{speech=w.modelSettings.activeSpeech;text=w.modelSettings.activeText}
 }
 @AppStorage("vt.motionEnabled") private var motionEnabled=true
 private var recordingSection:some View {
  VStack(alignment:.leading,spacing:22){
   Text("录音与AI整理").font(.title3.bold())
   Toggle("录音时自动整理（发送已确认逐字稿至所选整理服务商）",isOn:$w.liveEnabled).onChange(of:w.liveEnabled){value in UserDefaults.standard.set(value,forKey:"vt.liveEnabled")}.disabled(w.busy)
   Picker("实时整理间隔",selection:$w.liveInterval){Text("30秒").tag(30.0);Text("60秒").tag(60.0);Text("120秒").tag(120.0)}.onChange(of:w.liveInterval){value in UserDefaults.standard.set(value,forKey:"vt.liveInterval")}.disabled(w.busy)
   Toggle("结束录音后自动生成最终整理",isOn:$w.finalAuto).onChange(of:w.finalAuto){value in UserDefaults.standard.set(value,forKey:"vt.finalAuto")}.disabled(w.busy)
   Text("两个开关分别生效。整理会将已确认逐字稿发送给当前所选服务商，可能产生费用；关闭后仍可手动整理。").font(.callout).foregroundStyle(p.muted)
   Text("语音："+w.modelSettings.activeSpeech.name+" · 整理："+w.modelSettings.activeText.name).font(.callout)
   Button("检查可恢复录音"){w.settings=false;DispatchQueue.main.asyncAfter(deadline:.now()+0.35){w.scanRecovery()}}.disabled(w.busy)
   Text("恢复仅在本机进行，原始录音保留。恢复后可自行选择补转写。").font(.caption).foregroundStyle(p.muted)
  }.padding(.vertical,18)
 }
 private var appearanceSection:some View {
  VStack(alignment:.leading,spacing:24){
   Text("工作氛围").font(.title3.bold())
   Text("选择适合当下的配色，应用立即生效。").foregroundStyle(p.muted)
   LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:16){
    ForEach(["燕麦森林","沙色灰蓝","芒果","秋日"],id:\.self){name in
     Button{w.theme=name;UserDefaults.standard.set(name,forKey:"nativeTheme")} label:{
      HStack(spacing:14){Circle().fill(Palette.named(name).accent).frame(width:26,height:26);Text(name);Spacer();if w.theme==name{Image(systemName:"checkmark.circle.fill").foregroundStyle(Palette.named(name).accent)}}.padding(18).background(Palette.named(name).side).clipShape(RoundedRectangle(cornerRadius:10))
     }.buttonStyle(.plain).accessibilityLabel(name+(w.theme==name ? "，已选中":""))
    }
   }
   Toggle("轻量动效",isOn:$motionEnabled)
   Text("系统开启“减少动态效果”时，应用会优先采用静态状态。页面切换和AI侧栏只做轻量过渡，不干扰阅读。").font(.caption).foregroundStyle(p.muted)
  }.padding(.vertical,18).padding(.horizontal,6)
 }
 private var paddingDivider:some View{p.border.frame(width:0.5)}
 private var speechSection:some View {
  VStack(alignment:.leading,spacing:13){
   Text("语音识别").font(.headline)
   Text("当前使用："+w.modelSettings.activeSpeech.name).font(.caption).foregroundStyle(p.muted)
   Picker("已存配置",selection:Binding(get:{speech.id},set:{id in if let p=w.modelSettings.speech.first(where:{$0.id==id}){speech=p;ali="";feedback=""}})){
    ForEach(w.modelSettings.speech){p in Text(p.name).tag(p.id)}
    if !w.modelSettings.speech.contains(where:{$0.id==speech.id}){Text("新配置（未保存）").tag(speech.id)}
   }
   Button("新建语音配置"){speech=SpeechProfile();speech.name="新语音配置";ali="";feedback=""}
   FormField(title:"配置名称"){TextField("例如：百炼北京",text:$speech.name)}
   Text("服务商：阿里云百炼").font(.callout)
   FormField(title:"服务地域"){Picker("地域",selection:$speech.region){Text("北京").tag("cn-beijing");Text("新加坡").tag("ap-southeast-1")}.labelsHidden()}
   FormField(title:"Workspace ID",hint:"业务空间 ID，需与地域和密钥一致。"){TextField("填写业务空间 ID",text:$speech.workspace).focused($focused,equals:"workspace")}
   if !speech.workspace.isEmpty && !Wire.validateWorkspace(speech.workspace){Text("仅使用字母、数字和短横线，请检查是否多复制了空格。").font(.caption).foregroundStyle(p.danger)}
   FormField(title:"实时转写模型"){TextField("fun-asr-realtime",text:$speech.realtimeModel)}
   Text("支持Fun-ASR-Realtime及其版本模型；其他实时协议需另行适配。").font(.caption).foregroundStyle(p.muted)
   Picker("会后转写 / 发言人",selection:$speech.fileModel){Text("Fun-ASR").tag("fun-asr");Text("Paraformer v2").tag("paraformer-v2");Text("Qwen Audio 3.0 Filetrans").tag("qwen-audio-3.0-asr-flash-filetrans")}
   FormField(title:"百炼 API Key",hint:Vault.exists(speech.keyAccount) ? "已保存，留空继续使用现有密钥。":"密钥仅保存到这台 Mac 的钥匙串。"){SecureField("填写或保持留空",text:$ali)}
   Text("接口由地域及Workspace ID自动生成。").font(.caption).foregroundStyle(p.muted)
   if let issue=speechIssue{Text(issue).font(.system(size:12)).foregroundStyle(p.danger)}
   Button("测试实时连接"){testSpeech()}
  }.textFieldStyle(.roundedBorder).controlSize(.large).frame(maxWidth:.infinity,alignment:.leading).disabled(unavailable)
 }
 private var textSection:some View {
  VStack(alignment:.leading,spacing:13){
   Text("会议整理大模型").font(.headline)
   Text("当前使用："+w.modelSettings.activeText.name).font(.caption).foregroundStyle(p.muted)
   Picker("已存配置",selection:Binding(get:{text.id},set:{id in if let p=w.modelSettings.texts.first(where:{$0.id==id}){text=p;deep="";feedback=""}})){
    ForEach(w.modelSettings.texts){p in Text(p.name).tag(p.id)}
    if !w.modelSettings.texts.contains(where:{$0.id==text.id}){Text("新配置（未保存）").tag(text.id)}
   }
   Button("新建整理配置"){text=TextProfile();text.name="新整理配置";deep="";feedback=""}
   FormField(title:"配置名称"){TextField("例如：DeepSeek",text:$text.name)}
   Picker("接口类型",selection:$text.provider){Text("DeepSeek官方").tag("deepseek");Text("Chat Completions兼容接口").tag("compatible")}
   FormField(title:"接口基础地址"){TextField("https://api.deepseek.com",text:$text.baseURL).focused($focused,equals:"baseURL")}
   Text("兼容服务通常填写含/v1的基础地址；程序自动附加/chat/completions。").font(.caption).foregroundStyle(p.muted)
   FormField(title:"整理模型名称"){TextField("填写服务商支持的模型名称",text:$text.model)}
   FormField(title:"整理服务 API Key",hint:Vault.exists(text.keyAccount) ? "已保存，留空继续使用现有密钥。":"切换服务地址后，请配置对应服务的密钥。"){SecureField("填写或保持留空",text:$deep)}
   Text("纪要、思维链、分歧点、章节、待办及问答均使用当前配置。切换服务地址须配置该服务的密钥。").font(.caption).foregroundStyle(p.muted)
   if let issue=textIssue{Text(issue).font(.system(size:12)).foregroundStyle(p.danger)}
   Button("测试整理连接"){testText()}
  }.textFieldStyle(.roundedBorder).controlSize(.large).frame(maxWidth:.infinity,alignment:.leading).disabled(unavailable)
 }
 private var speechIssue:String?{guard !speech.workspace.isEmpty else{return nil};do{_=try speech.validated();return nil}catch{return (error as? AppError)?.message}}
 private var textIssue:String?{guard !text.baseURL.isEmpty else{return "请填写接口基础地址"};do{_=try text.validated();return nil}catch{return (error as? AppError)?.message}}
 private func saveSpeech(){do{try w.saveSpeechProfile(speech,key:ali);speech=w.modelSettings.activeSpeech;ali="";feedback="语音配置已保存并启用。"}catch{show(error)}}
 private func saveText(){do{try w.saveTextProfile(text,key:deep);text=w.modelSettings.activeText;deep="";feedback="整理配置已保存并启用。"}catch{show(error)}}
 private func show(_ error:Error){feedback=(error as? AppError)?.message ?? "连接未完成，请检查网络、接口地址、密钥和模型权限。"}
 private func testSpeech(){
  do {let profile=try speech.validated();let key=ali.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? Vault.read(profile.keyAccount):ali.trimmingCharacters(in:.whitespacesAndNewlines)
   testing=true;feedback="正在测试实时连接…"
   let config=ServiceConfig(speech:profile,text:w.modelSettings.activeText)
   Task{defer{testing=false};do{feedback=try await Cloud(config:config).testSpeech(key:key)}catch{show(error)}}
  }catch{show(error)}
 }
 private func testText(){
  do {let profile=try text.validated();let key=deep.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? Vault.read(profile.keyAccount):deep.trimmingCharacters(in:.whitespacesAndNewlines)
   testing=true;feedback="正在测试整理连接…"
   let config=ServiceConfig(speech:w.modelSettings.activeSpeech,text:profile)
   Task{defer{testing=false};do{feedback=try await Cloud(config:config).testText(key:key)}catch{show(error)}}
  }catch{show(error)}
 }
}
