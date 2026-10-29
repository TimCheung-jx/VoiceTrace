import AVFoundation
import Foundation

@main struct AudioChecks {
  static func main() throws {
    let converter = PCMStreamConverter()
    for (rate, channels) in [
      (16000.0, 1), (44100.0, 1), (48000.0, 2), (32000.0, 1), (8000.0, 1), (96000.0, 1),
      (192000.0, 2),
    ] {
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: AVAudioChannelCount(channels),
        interleaved: false)!
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048)!
      buffer.frameLength = 2048
      var bytes = 0
      for n in 0..<30 {
        for channel in 0..<channels {
          for i in 0..<2048 {
            buffer.floatChannelData![channel][i] = Float(
              sin(Double(n * 2048 + i) * 440 * 2 * Double.pi / rate) * 0.2)
          }
        }
        let (data, level) = try converter.convert(buffer)
        bytes += data.count
        precondition(level.isFinite && level >= 0 && level <= 1)
      }
      let expected = Double(2048 * 30) / rate
      precondition(abs(Double(bytes) / 32000 - expected) < 0.06)
    }
    let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    let empty = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32)!
    let emptyResult = try converter.convert(empty)
    precondition(emptyResult.0.isEmpty)
    let unusual = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048)!
    unusual.frameLength = 2048
    for i in 0..<2048 {
      unusual.floatChannelData![0][i] = i % 3 == 0 ? .nan : i % 3 == 1 ? .infinity : 3
    }
    let result = try converter.convert(unusual)
    precondition(!result.0.isEmpty && result.1.isFinite)
    func tone(_ frequency: Double, chunks: Int = 50) throws -> Data {
      let c = PCMStreamConverter()
      let f = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
      let packet = 48000 / chunks
      let b = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(packet))!
      b.frameLength = AVAudioFrameCount(packet)
      var collected = Data()
      for n in 0..<chunks {
        for i in 0..<packet {
          b.floatChannelData![0][i] = Float(
            sin(Double(n * packet + i) * frequency * 2 * Double.pi / 48000) * 0.2)
        }
        collected.append(try c.convert(b).0)
      }
      return collected
    }
    func rms(_ data: Data) -> Double {
      var total: Double = 0
      for i in stride(from: 0, to: data.count - 1, by: 2) {
        let v = Double(Int16(bitPattern: UInt16(data[i]) | UInt16(data[i + 1]) << 8)) / 32768
        total += v * v
      }
      return sqrt(total / Double(max(1, data.count / 2)))
    }
    let split = try tone(1000)
    let whole = try tone(1000, chunks: 1)
    precondition(split == whole)
    let speechBand = rms(split)
    let rejectedBand = rms(try tone(12000))
    precondition(speechBand > 0.12 && rejectedBand < 0.015)
    let stereo = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 2, interleaved: true)!
    let interleaved = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 128)!
    interleaved.frameLength = 128
    let list = UnsafeMutableAudioBufferListPointer(interleaved.mutableAudioBufferList)
    let floats = list[0].mData!.assumingMemoryBound(to: Float.self)
    for i in 0..<128 {
      floats[2 * i] = 0.2
      floats[2 * i + 1] = -0.2
    }
    let mixed = try PCMStreamConverter().convert(interleaved).0
    precondition(rms(mixed) < 0.001)
    print("PASS: 语音频段保留、高频抗混叠，以及交错双声道混合。")
    var budget = AudioRecoveryBudget()
    precondition(
      !AudioRecoveryBudget.needsRecovery(engineRunning: true, actual: "48k:2", expected: "48k:2"))
    precondition(
      AudioRecoveryBudget.needsRecovery(engineRunning: false, actual: "48k:2", expected: "48k:2"))
    precondition(
      AudioRecoveryBudget.needsRecovery(engineRunning: true, actual: "32k:1", expected: "48k:2"))
    precondition(
      budget.allow(at: 1) && budget.allow(at: 2) && budget.allow(at: 3) && !budget.allow(at: 4)
        && budget.allow(at: 12))
    print(
      "PASS: 实际PCM转换器离线处理16/32/44.1/48kHz、单/双声道及格式切换；空预热缓冲、非有限值、裁剪；无效配置通知过滤和恢复次数限制。未开启麦克风或访问网络。"
    )
  }
}
