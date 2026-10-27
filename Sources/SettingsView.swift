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
 private var unavailable:Bool {w.locked || testing}
 var body:some View {
  VStack(alignment:.leading,spacing:16){
   Text("声迹设置").font(.title2.bold())
   Text("保存多套配置，按需切换。密钥保存在本机钥匙串，输入留空保持已保存密钥。").font(.callout).foregroundStyle(.secondary)
   if w.locked {Text("当前任务进行中，可查看设置；结束后可保存、切换或测试。").foregroundStyle(.orange)}
   Picker("设置分类",selection:$w.settingsPage){Text("外观").tag("外观");Text("模型与服务").tag("模型与服务")}.pickerStyle(.segmented)
   ScrollView {
    if w.settingsPage=="外观" {appearanceSection}else{HStack(alignment:.top,spacing:28){speechSection;textSection}}
   }
   Divider()
   HStack {if testing{ProgressView().controlSize(.small)};Text(feedback).font(.callout).textSelection(.enabled);Spacer();Button("完成"){w.settings=false}.disabled(testing)}
   Text("语音测试只建立实时任务，不采集麦克风；整理测试只发送固定虚构文字。测试可能产生服务费用。会后识别模型仍需用短录音验证。").font(.caption).foregroundStyle(.secondary)
  }.padding(26).frame(width:850,height:730)
  .onAppear{speech=w.modelSettings.activeSpeech;text=w.modelSettings.activeText}
 }
 @AppStorage("vt.motionEnabled") private var motionEnabled=true
 private var appearanceSection:some View {
  VStack(alignment:.leading,spacing:24){
   Text("工作氛围").font(.title3.bold())
   Text("选择适合当下的配色，应用立即生效。").foregroundStyle(.secondary)
   LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:16){
    ForEach(["燕麦森林","沙色灰蓝","芒果","秋日"],id:\.self){name in
     Button{w.theme=name;UserDefaults.standard.set(name,forKey:"nativeTheme")} label:{
      HStack(spacing:14){Circle().fill(Palette.named(name).accent).frame(width:26,height:26);Text(name);Spacer();if w.theme==name{Image(systemName:"checkmark.circle.fill").foregroundStyle(Palette.named(name).accent)}}.padding(18).background(Palette.named(name).side).clipShape(RoundedRectangle(cornerRadius:10))
     }.buttonStyle(.plain).accessibilityLabel(name+(w.theme==name ? "，已选中":""))
    }
   }
   Toggle("轻量动效",isOn:$motionEnabled)
   Text("系统开启“减少动态效果”时，应用会优先采用静态状态。页面切换和AI侧栏只做轻量过渡，不干扰阅读。").font(.caption).foregroundStyle(.secondary)
  }.padding(.vertical,18).padding(.horizontal,6)
 }
 private var speechSection:some View {
  VStack(alignment:.leading,spacing:13){
   Text("语音识别").font(.headline)
   Text("当前使用："+w.modelSettings.activeSpeech.name).font(.caption).foregroundStyle(.secondary)
   Picker("已存配置",selection:Binding(get:{speech.id},set:{id in if let p=w.modelSettings.speech.first(where:{$0.id==id}){speech=p;ali="";feedback=""}})){
    ForEach(w.modelSettings.speech){p in Text(p.name).tag(p.id)}
    if !w.modelSettings.speech.contains(where:{$0.id==speech.id}){Text("新配置（未保存）").tag(speech.id)}
   }
   Button("＋ 新建语音配置"){speech=SpeechProfile();speech.name="新语音配置";ali="";feedback=""}
   TextField("配置名称",text:$speech.name)
   Text("服务商：阿里云百炼").font(.callout)
   Picker("地域",selection:$speech.region){Text("北京").tag("cn-beijing");Text("新加坡").tag("ap-southeast-1")}
   TextField("Workspace ID（业务空间ID）",text:$speech.workspace)
   Text("实时转写模型").font(.caption).foregroundStyle(.secondary)
   TextField("fun-asr-realtime",text:$speech.realtimeModel)
   Text("支持Fun-ASR-Realtime及其版本模型；其他实时协议需另行适配。").font(.caption).foregroundStyle(.secondary)
   Picker("会后转写 / 发言人",selection:$speech.fileModel){Text("Fun-ASR").tag("fun-asr");Text("Paraformer v2").tag("paraformer-v2");Text("Qwen Audio 3.0 Filetrans").tag("qwen-audio-3.0-asr-flash-filetrans")}
   SecureField(Vault.exists(speech.keyAccount) ? "密钥已保存（留空保持）":"填写百炼 API Key",text:$ali)
   Text("接口由地域及Workspace ID自动生成。").font(.caption).foregroundStyle(.secondary)
   Button("测试实时连接"){testSpeech()}
   Button("保存并使用语音配置"){do{try w.saveSpeechProfile(speech,key:ali);speech=w.modelSettings.activeSpeech;ali="";feedback="语音配置已保存并启用。"}catch{show(error)}}.buttonStyle(.borderedProminent)
  }.textFieldStyle(.roundedBorder).frame(maxWidth:.infinity,alignment:.leading).disabled(unavailable)
 }
 private var textSection:some View {
  VStack(alignment:.leading,spacing:13){
   Text("会议整理大模型").font(.headline)
   Text("当前使用："+w.modelSettings.activeText.name).font(.caption).foregroundStyle(.secondary)
   Picker("已存配置",selection:Binding(get:{text.id},set:{id in if let p=w.modelSettings.texts.first(where:{$0.id==id}){text=p;deep="";feedback=""}})){
    ForEach(w.modelSettings.texts){p in Text(p.name).tag(p.id)}
    if !w.modelSettings.texts.contains(where:{$0.id==text.id}){Text("新配置（未保存）").tag(text.id)}
   }
   Button("＋ 新建整理配置"){text=TextProfile();text.name="新整理配置";deep="";feedback=""}
   TextField("配置名称",text:$text.name)
   Picker("接口类型",selection:$text.provider){Text("DeepSeek官方").tag("deepseek");Text("Chat Completions兼容接口").tag("compatible")}
   Text("接口基础地址").font(.caption).foregroundStyle(.secondary)
   TextField("https://api.deepseek.com",text:$text.baseURL)
   Text("兼容服务通常填写含/v1的基础地址；程序自动附加/chat/completions。").font(.caption).foregroundStyle(.secondary)
   TextField("模型名称",text:$text.model)
   SecureField(Vault.exists(text.keyAccount) ? "密钥已保存（留空保持）":"填写整理服务 API Key",text:$deep)
   Text("纪要、思维链、分歧点、章节、待办及问答均使用当前配置。切换服务地址须配置该服务的密钥。").font(.caption).foregroundStyle(.secondary)
   Button("测试整理连接"){testText()}
   Button("保存并使用整理配置"){do{try w.saveTextProfile(text,key:deep);text=w.modelSettings.activeText;deep="";feedback="整理配置已保存并启用。"}catch{show(error)}}.buttonStyle(.borderedProminent)
  }.textFieldStyle(.roundedBorder).frame(maxWidth:.infinity,alignment:.leading).disabled(unavailable)
 }
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
