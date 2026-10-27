import Foundation
// 仅在进程内保存成功取得的凭据，不写入磁盘或日志。
final class MemoryCredentials {
 private var values:[String:String]=[:]
 private let lock=NSLock()
 func value(for account:String,load:()->String?) -> String? {
  lock.lock();defer{lock.unlock()}
  if let cached=values[account]{return cached}
  guard let value=load(),!value.isEmpty else{return nil}
  values[account]=value;return value
 }
 func contains(_ account:String)->Bool {
  lock.lock();defer{lock.unlock()};return values[account] != nil
 }
 func save(_ account:String,value:String,persist:()throws->Void) throws {
  lock.lock();defer{lock.unlock()}
  guard !value.isEmpty else{return}
  if values[account]==value{return}
  try persist();values[account]=value
 }
 func clear(){lock.lock();defer{lock.unlock()};values.removeAll()}
}
