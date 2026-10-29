import AVFoundation
import Foundation

// 连续有界的PCM处理：混合声道、抗混叠重采样，避免分包转换器持有临时缓冲。
// 16kHz输入直接转换；其他采样率使用有状态的窗函数sinc滤波，跨包保留相位。
final class PCMStreamConverter {
  private var rate: Double = 0
  private var samples: [Float] = []
  private var position: Double = 0
  private var radius = 16
  private var kernels: [[Float]] = []
  func convert(_ buffer: AVAudioPCMBuffer) throws -> (Data, Float) {
    guard buffer.frameLength > 0 else { return (Data(), 0) }
    let frames = Int(buffer.frameLength)
    let channels = Int(buffer.format.channelCount)
    let sourceRate = buffer.format.sampleRate
    guard sourceRate.isFinite, sourceRate >= 8000, sourceRate <= 192000, channels > 0,
      channels <= 32
    else { throw AppError("麦克风采样率或声道不受支持") }
    let blocks = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
    let interleaved = buffer.format.isInterleaved
    let stride = interleaved ? channels : 1
    var mono = [Float](repeating: 0, count: frames)
    func add<T>(_ type: T.Type, value: (T) -> Float) throws {
      for channel in 0..<channels {
        let blockIndex = interleaved ? 0 : channel
        let offset = interleaved ? channel : 0
        guard blockIndex < blocks.count, let memory = blocks[blockIndex].mData,
          ((frames - 1) * stride + offset + 1) * MemoryLayout<T>.stride
            <= Int(blocks[blockIndex].mDataByteSize)
        else { throw AppError("音频缓冲长度无效") }
        let pointer = memory.assumingMemoryBound(to: T.self)
        for frame in 0..<frames {
          let sample = value(pointer[frame * stride + offset])
          mono[frame] += (sample.isFinite ? sample : 0) / Float(channels)
        }
      }
    }
    switch buffer.format.commonFormat {
    case .pcmFormatFloat32: try add(Float.self) { $0 }
    case .pcmFormatFloat64: try add(Double.self) { Float($0) }
    case .pcmFormatInt16: try add(Int16.self) { Float($0) / 32768 }
    case .pcmFormatInt32: try add(Int32.self) { Float($0) / 2_147_483_648 }
    default: throw AppError("麦克风PCM格式不受支持")
    }
    let output: [Float]
    if sourceRate == 16000 {
      if rate != 16000 {
        rate = 16000
        samples = []
        kernels = []
        position = 0
      }
      output = mono
    } else {
      if sourceRate != rate {
        rate = sourceRate
        radius = 16 * Int(ceil(max(1, rate / 16000)))
        samples = [Float](repeating: 0, count: radius + 1)
        position = Double(radius + 1)
        let cutoff = 0.45 * min(1, 16000 / rate)
        kernels = (0..<256).map { phase in
          let fraction = Double(phase) / 256
          var weights = (-radius + 1...radius).map { tap -> Double in
            let x = Double(tap) - fraction
            let sinc =
              abs(x) < 0.000001 ? 2 * cutoff : sin(2 * Double.pi * cutoff * x) / (Double.pi * x)
            let window =
              abs(x) <= Double(radius) ? 0.5 + 0.5 * cos(Double.pi * x / Double(radius)) : 0
            return sinc * window
          }
          let total = weights.reduce(0, +)
          for i in weights.indices { weights[i] /= total }
          return weights.map(Float.init)
        }
      }
      samples.append(contentsOf: mono)
      var resampled: [Float] = []
      resampled.reserveCapacity(Int(Double(frames) * 16000 / rate) + 2)
      while position + Double(radius) < Double(samples.count) {
        let base = Int(position)
        let phase = min(255, Int((position - Double(base)) * 256))
        let weights = kernels[phase]
        var sum: Float = 0
        for index in weights.indices { sum += samples[base - radius + 1 + index] * weights[index] }
        resampled.append(sum)
        position += rate / 16000
      }
      let drop = max(0, Int(position) - radius - 1)
      if drop > 0 {
        samples.removeFirst(min(drop, samples.count))
        position -= Double(drop)
      }
      output = resampled
    }
    var sum: Float = 0
    var data = Data(capacity: output.count * 2)
    for raw in output {
      let sample = raw.isFinite ? max(-1, min(1, raw)) : 0
      sum += sample * sample
      var value = Int16(max(-32768, min(32767, Int(sample * 32767)))).littleEndian
      withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
    return (data, output.isEmpty ? 0 : min(1, sqrt(sum / Float(output.count)) * 5))
  }
}

struct AudioRecoveryBudget {
  private var attempts: [TimeInterval] = []
  mutating func allow(at now: TimeInterval) -> Bool {
    attempts = attempts.filter { now - $0 < 10 }
    guard attempts.count < 3 else { return false }
    attempts.append(now)
    return true
  }
  static func needsRecovery(engineRunning: Bool, actual: String, expected: String) -> Bool {
    !engineRunning || actual != expected
  }
}

// 音频控制、格式恢复与文件写入分开排队；配置变化时恢复引擎，不直接让录音闪停。
final class AudioCapture {
  private let engine = AVAudioEngine()
  private let control = DispatchQueue(label: "org.voicetrace.audio.control", qos: .userInitiated)
  private let queue = DispatchQueue(label: "org.voicetrace.app.audio", qos: .userInitiated)
  private var file: FileHandle?
  private var bytes: UInt32 = 0
  private var pcmURL: URL?
  private var running = false
  private var tapped = false
  private var deviceObserver: NSObjectProtocol?
  private var recovery: DispatchWorkItem?
  private var inputWatch: DispatchWorkItem?
  private var recoveryBudget = AudioRecoveryBudget()
  private var signature = ""
  private var generation = UUID()
  private var yield: (Data) -> Void = { _ in }
  private var level: (Float) -> Void = { _ in }
  private var interrupted: () -> Void = {}
  private var fail: () -> Void = {}
  var onEvent: ((String, Int) -> Void)?
  deinit {
    if let observer = deviceObserver { NotificationCenter.default.removeObserver(observer) }
  }
  func start(
    directory: URL, offset: Double = 0, yield: @escaping (Data) -> Void,
    level: @escaping (Float) -> Void = { _ in }, interrupted: @escaping () -> Void = {},
    fail: @escaping () -> Void = {}
  ) throws {
    try control.sync {
      guard !running else { return }
      self.yield = yield
      self.level = level
      self.interrupted = interrupted
      self.fail = fail
      generation = UUID()
      recoveryBudget = AudioRecoveryBudget()
      let url = directory.appendingPathComponent("audio-\(UUID().uuidString).pcm")
      guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
        throw AppError("无法创建录音文件")
      }
      let handle = try FileHandle(forWritingTo: url)
      do {
        try JSONEncoder().encode(CaptureJournal(offset: offset)).write(
          to: url.appendingPathExtension("capture.json"), options: .atomic)
      } catch {
        try? handle.close()
        throw AppError("无法保存录音恢复信息，请检查磁盘和目录权限")
      }
      queue.sync {
        self.file = handle
        self.pcmURL = url
        self.bytes = 0
      }
      do {
        running = true
        try configure()
        deviceObserver = NotificationCenter.default.addObserver(
          forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
          // Apple要求不要在通知的内部队列同步拆卸引擎。
          self?.control.async { [weak self] in self?.scheduleRecovery() }
        }
        onEvent?("engine_started", 0)
        scheduleInputWatch()
      } catch {
        running = false
        if tapped {
          engine.inputNode.removeTap(onBus: 0)
          tapped = false
        }
        queue.sync {
          try? self.file?.close()
          self.file = nil
        }
        onEvent?("engine_start_failed", (error as NSError).code)
        throw AppError("麦克风启动失败，请检查麦克风权限及输入设备")
      }
    }
  }
  private func currentSignature() -> String {
    let format = engine.inputNode.outputFormat(forBus: 0)
    return "\(format.sampleRate):\(format.channelCount)"
  }
  private func configure() throws {
    engine.stop()
    let input = engine.inputNode
    if tapped {
      input.removeTap(onBus: 0)
      tapped = false
    }
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else { throw AppError("麦克风格式暂不可用") }
    signature = currentSignature()
    let converter = PCMStreamConverter()
    let token = generation
    var conversionErrors = 0
    input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
      guard let self = self, buffer.frameLength > 0,
        let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
      else { return }
      copy.frameLength = buffer.frameLength
      let src = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
      let dst = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
      for i in 0..<min(src.count, dst.count) {
        if let a = src[i].mData, let b = dst[i].mData {
          memcpy(b, a, min(Int(src[i].mDataByteSize), Int(dst[i].mDataByteSize)))
        }
      }
      self.queue.async {
        let converted: (Data, Float)
        do {
          converted = try converter.convert(copy)
          conversionErrors = 0
        } catch {
          conversionErrors += 1
          if conversionErrors == 1 || conversionErrors == 3 {
            self.onEvent?("conversion_error", (error as NSError).code)
          }
          if conversionErrors == 3 {
            self.control.async { [weak self] in
              guard let self = self, self.generation == token, self.running else { return }
              self.scheduleRecovery(force: true)
            }
          }
          return
        }
        let (data, energy) = converted
        guard !data.isEmpty, let file = self.file else { return }
        guard UInt64(self.bytes) + UInt64(data.count) <= UInt64(UInt32.max) - 44 else {
          self.onEvent?("file_size_limit", 0)
          self.fail()
          return
        }
        do {
          try file.write(contentsOf: data)
          self.bytes += UInt32(data.count)
          self.level(energy)
          self.yield(data)
        } catch {
          self.onEvent?("file_write_error", (error as NSError).code)
          self.fail()
        }

      }
    }
    tapped = true
    engine.prepare()
    try engine.start()
  }
  private func scheduleRecovery(force: Bool = false) {
    guard running else { return }
    if !force,
      !AudioRecoveryBudget.needsRecovery(
        engineRunning: engine.isRunning, actual: currentSignature(), expected: signature)
    {
      onEvent?("configuration_stable", 0)
      return
    }
    recovery?.cancel()
    inputWatch?.cancel()
    let token = generation
    let work = DispatchWorkItem { [weak self] in
      guard let self = self, self.running, self.generation == token else { return }
      let now = ProcessInfo.processInfo.systemUptime
      guard self.recoveryBudget.allow(at: now) else {
        self.onEvent?("engine_recovery_exhausted", 0)
        self.interrupted()
        return
      }
      self.onEvent?("engine_recovering", 0)
      do {
        try self.configure()
        self.onEvent?("engine_recovered", 0)
        self.scheduleInputWatch()
      } catch {
        self.onEvent?("engine_recovery_failed", (error as NSError).code)
        self.scheduleRecovery(force: true)
      }
    }
    recovery = work
    control.asyncAfter(deadline: .now() + 0.25, execute: work)
  }
  private func scheduleInputWatch() {
    inputWatch?.cancel()
    let token = generation
    let previous = queue.sync { bytes }
    let work = DispatchWorkItem { [weak self] in
      guard let self = self, self.running, self.generation == token else { return }
      let current = self.queue.sync { self.bytes }
      if current == previous {
        self.onEvent?("no_audio_buffers", 0)
        self.scheduleRecovery(force: true)
      } else {
        self.scheduleInputWatch()
      }
    }
    inputWatch = work
    control.asyncAfter(deadline: .now() + 2, execute: work)
  }
  func duration() -> Double { queue.sync { Double(bytes) / 32000 } }
  func stop() throws -> (URL, Double)? {
    try control.sync {
      guard running else { return nil }
      running = false
      generation = UUID()
      recovery?.cancel()
      inputWatch?.cancel()
      if let observer = deviceObserver {
        NotificationCenter.default.removeObserver(observer)
        deviceObserver = nil
      }
      engine.stop()
      if tapped {
        engine.inputNode.removeTap(onBus: 0)
        tapped = false
      }
      return try queue.sync {
        try file?.close()
        file = nil
        guard let pcm = pcmURL else { return nil }
        let wav = pcm.deletingPathExtension().appendingPathExtension("wav")
        guard
          FileManager.default.createFile(atPath: wav.path, contents: Wire.wavHeader(bytes: bytes))
        else { throw AppError("无法保存录音文件头") }
        let output = try FileHandle(forWritingTo: wav)
        try output.seekToEnd()
        let input = try FileHandle(forReadingFrom: pcm)
        defer {
          try? input.close()
          try? output.close()
        }
        while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty {
          try output.write(contentsOf: data)
        }
        return (wav, Double(bytes) / 32000)
      }
    }
  }
}
