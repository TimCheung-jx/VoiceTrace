import Foundation

struct VTRecovery: Identifiable {
  let documentID: String
  let pcm: URL
  let offset: Double
  let byteCount: Int
  var id: String { pcm.path }
  var target: URL { pcm.deletingPathExtension().appendingPathExtension("next-recovered.wav") }
  static func scan(repository: VTRepository) throws -> [Self] {
    var found: [Self] = []
    for doc in try repository.list() {
      let folder = repository.root.appendingPathComponent("audio").appendingPathComponent(doc.id)
      let files =
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))
        ?? []
      for file in files where file.pathExtension == "pcm" {
        let expected = file.deletingPathExtension().appendingPathExtension("wav")
        if doc.audio.contains(where: {
          $0.path == expected.path
            || (URL(fileURLWithPath: $0.path).deletingLastPathComponent().standardizedFileURL.path
              == folder.standardizedFileURL.path
              && URL(fileURLWithPath: $0.path).lastPathComponent.hasPrefix(
                file.deletingPathExtension().lastPathComponent + ".next-recovered"))
        }) {
          continue
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
          let bytes = (attrs[.size] as? NSNumber)?.intValue, bytes >= 2,
          bytes <= Int(UInt32.max) - 44
        else { continue }
        let data = try? Data(contentsOf: file.appendingPathExtension("capture.json"))
        let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let offset =
          (json?["offset"] as? NSNumber)?.doubleValue ?? doc.audio.reduce(0, { $0 + $1.duration })
        found.append(
          Self(documentID: doc.id, pcm: file, offset: offset, byteCount: bytes - bytes % 2))
      }
    }
    return found
  }
  func recover() throws -> VTAudio {
    let fm = FileManager.default
    func size(_ url: URL) -> Int? {
      ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue
    }
    if size(target) == byteCount + 44 {
      return VTAudio(path: target.path, offset: offset, duration: Double(byteCount) / 32000)
    }
    let destination =
      fm.fileExists(atPath: target.path)
      ? pcm.deletingPathExtension().appendingPathExtension(
        "next-recovered-" + UUID().uuidString + ".wav") : target
    let staging = pcm.appendingPathExtension("recovering-" + UUID().uuidString)
    var header = Data()
    func ascii(_ s: String) { header.append(Data(s.utf8)) }
    func u32(_ v: UInt32) {
      var n = v.littleEndian
      withUnsafeBytes(of: &n) { header.append(contentsOf: $0) }
    }
    func u16(_ v: UInt16) {
      var n = v.littleEndian
      withUnsafeBytes(of: &n) { header.append(contentsOf: $0) }
    }
    ascii("RIFF")
    u32(UInt32(byteCount) + 36)
    ascii("WAVEfmt ")
    u32(16)
    u16(1)
    u16(1)
    u32(16000)
    u32(32000)
    u16(2)
    u16(16)
    ascii("data")
    u32(UInt32(byteCount))
    try header.write(to: staging, options: .withoutOverwriting)
    let input = try FileHandle(forReadingFrom: pcm)
    let output = try FileHandle(forWritingTo: staging)
    defer {
      try? input.close()
      try? output.close()
    }
    try output.seekToEnd()
    var remaining = byteCount
    while remaining > 0, let bytes = try input.read(upToCount: min(remaining, 1024 * 1024)),
      !bytes.isEmpty
    {
      try output.write(contentsOf: bytes)
      remaining -= bytes.count
    }
    guard remaining == 0 else { throw VTError.message("恢复时原始录音长度变化，原件和中间文件均已保留") }
    try output.synchronize()
    try output.close()
    guard size(staging) == byteCount + 44 else { throw VTError.message("恢复文件不完整，原件已保留") }
    try fm.moveItem(at: staging, to: destination)
    return VTAudio(path: destination.path, offset: offset, duration: Double(byteCount) / 32000)
  }
}
