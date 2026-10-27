import Foundation
@main struct Checks {
 static func main() throws {
  let memory=MemoryCredentials();var calls=0
  for _ in 0..<20{let value=memory.value(for:"speech.first"){calls+=1;return "synthetic-a"};precondition(value=="synthetic-a")}
  precondition(calls==1)
  precondition(memory.value(for:"speech.second"){calls+=1;return "synthetic-b"}=="synthetic-b" && calls==2)
  var writes=0
  try memory.save("speech.first",value:"synthetic-new"){writes+=1}
  precondition(memory.value(for:"speech.first"){preconditionFailure("不应重新读取系统密钥")}=="synthetic-new")
  try memory.save("speech.first",value:"synthetic-new"){writes+=1};precondition(writes==1)
  try memory.save("speech.first",value:""){preconditionFailure("空输入不应覆盖")}
  enum Failure:Error{case save}
  do{try memory.save("speech.first",value:"synthetic-failed"){throw Failure.save};preconditionFailure("应报告保存失败")}catch{}
  precondition(memory.value(for:"speech.first"){nil}=="synthetic-new")
  var attempts=0
  _=memory.value(for:"denied"){attempts+=1;return nil};_=memory.value(for:"denied"){attempts+=1;return "synthetic-retry"};precondition(attempts==2)
  memory.clear();precondition(!memory.contains("speech.first"));_=memory.value(for:"speech.first"){calls+=1;return "synthetic-reloaded"};precondition(calls==3)
  print("通过：20次读取仅首次加载、配置隔离、更新同步、同值不重复保存、空值保持、保存失败保留原缓存、授权失败可重试及退出清空。未访问真实钥匙串。")
 }
}
