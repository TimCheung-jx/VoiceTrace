import Foundation
import AVFoundation
// 采集、写盘与推送使用同一条顺序队列，结束时先清空写盘队列。
final class AudioCapture {
 private let engine = AVAudioEngine()
 private let queue = DispatchQueue(label:"org.voicetrace.app.audio")
 private var file: FileHandle?
 private var bytes: UInt32 = 0
 private var pcmURL: URL?
 private var running = false
 private var deviceObserver:NSObjectProtocol?
 deinit{if let observer=deviceObserver{NotificationCenter.default.removeObserver(observer)}}
 func start(directory:URL, offset:Double=0, yield:@escaping (Data)->Void, level:@escaping(Float)->Void={_ in}, interrupted:@escaping()->Void={}, fail:@escaping ()->Void) throws {
  let input=engine.inputNode; let format=input.outputFormat(forBus:0)
  guard format.sampleRate > 0, format.channelCount > 0, let target=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:16000,channels:1,interleaved:false), let converter=AVAudioConverter(from:format,to:target) else { throw AppError("无法访问麦克风，请检查系统声音输入设置") }
  let url=directory.appendingPathComponent("audio-\(UUID().uuidString).pcm")
  FileManager.default.createFile(atPath:url.path,contents:nil); file=try FileHandle(forWritingTo:url); pcmURL=url; bytes=0
  do{try JSONEncoder().encode(CaptureJournal(offset:offset)).write(to:url.appendingPathExtension("capture.json"),options:.atomic)}catch{try? file?.close();file=nil;throw AppError("无法保存录音恢复信息，请检查磁盘和目录权限")}
  input.installTap(onBus:0,bufferSize:4096,format:format) { [weak self] buffer,_ in
   guard let self=self else{return}
   // 复制 tap 缓冲，避免系统复用后后台队列读取失效。
   guard let copy=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:buffer.frameLength) else{return}
   copy.frameLength=buffer.frameLength
   let src=UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList), dst=UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
   for i in 0..<src.count { if let a=src[i].mData,let b=dst[i].mData { memcpy(b,a,Int(src[i].mDataByteSize)) } }
   self.queue.async {
    let capacity=AVAudioFrameCount(ceil(Double(copy.frameLength)*16000/format.sampleRate)+32)
    guard let output=AVAudioPCMBuffer(pcmFormat:target,frameCapacity:capacity) else{return}
    var supplied=false; var error:NSError?
    converter.convert(to:output,error:&error) { _,status in if supplied {status.pointee = .noDataNow; return nil}; supplied=true; status.pointee = .haveData; return copy }
    guard error == nil,let samples=output.floatChannelData?[0] else{fail();return}
    var sum:Float=0
    for i in 0..<Int(output.frameLength){sum += samples[i]*samples[i]}
    level(min(1,sqrt(sum/Float(max(1,Int(output.frameLength))))*5))
    var data=Data(capacity:Int(output.frameLength)*2)
    for i in 0..<Int(output.frameLength) { var v=Int16(max(-32768,min(32767,Int(samples[i]*32767)))).littleEndian; withUnsafeBytes(of:&v){data.append(contentsOf:$0)} }
    do { try self.file?.write(contentsOf:data); guard UInt64(self.bytes)+UInt64(data.count)<=UInt64(UInt32.max)-44 else{fail();return};self.bytes += UInt32(data.count); yield(data) } catch { fail() }
   }
  }
  do { try engine.start(); running=true;deviceObserver=NotificationCenter.default.addObserver(forName:.AVAudioEngineConfigurationChange,object:engine,queue:nil){_ in interrupted()} } catch { input.removeTap(onBus:0); try? file?.close(); file=nil; throw AppError("麦克风启动失败，请检查麦克风权限及输入设备") }
 }
 func duration() -> Double {queue.sync {Double(bytes)/32000}}
 func stop() throws -> (URL, Double)? {
  if let observer=deviceObserver{NotificationCenter.default.removeObserver(observer);deviceObserver=nil}
  guard running else{return nil}; running=false; engine.stop(); engine.inputNode.removeTap(onBus:0)
  return try queue.sync {
   try file?.close(); file=nil
   guard let pcm=pcmURL else{return nil}; let wav=pcm.deletingPathExtension().appendingPathExtension("wav")
   FileManager.default.createFile(atPath:wav.path,contents:Wire.wavHeader(bytes:bytes))
   let output=try FileHandle(forWritingTo:wav); try output.seekToEnd(); let input=try FileHandle(forReadingFrom:pcm)
   defer { try? input.close(); try? output.close() }
   while let data=try input.read(upToCount:1024*1024), !data.isEmpty {try output.write(contentsOf:data)}
   return (wav,Double(bytes)/32000)
  }
 }
}
