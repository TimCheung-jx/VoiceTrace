import Foundation
@main struct PersonalChecks {
 static func main() throws {
  let defaults=UserDefaults(suiteName:"vt-personal-test-"+UUID().uuidString)!
  defaults.set("ws-synthetic",forKey:"workspace");defaults.set("fun-asr-realtime",forKey:"realtimeModel");defaults.set("synthetic-model",forKey:"deepModel")
  let saved=SettingsFile.load(defaults)
  precondition(saved.activeSpeech.workspace=="ws-synthetic" && saved.activeSpeech.keyAccount=="aliyun")
  precondition(saved.activeText.keyAccount=="deepseek" && saved.activeText.model=="synthetic-model")
  var changed=saved.activeText;changed.baseURL="https://example.test/v1";precondition(changed.keyAccount != "deepseek")
  var speech=saved.activeSpeech;speech.workspace="other-synthetic";precondition(speech.keyAccount != "aliyun")
  try saved.save(defaults);let roundTrip=SettingsFile.load(defaults);precondition(roundTrip==saved)
  precondition(AppIdentity.personal && AppIdentity.dataDirectory=="听见会议资料")
  print("通过：个人版旧配置迁移、钥匙串账户映射、地址及空间变更隔离。使用虚构配置，未访问真实密钥。")
 }
}
