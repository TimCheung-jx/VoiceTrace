import AppKit
import CoreText
import SwiftUI

@MainActor enum VTExporter {
  static func filename(_ title: String, ext: String) -> String {
    let safe = title.components(separatedBy: CharacterSet(charactersIn: "/:\\\n\r\t")).joined(
      separator: "-")
    return String(safe.prefix(100)) + "." + ext
  }
  static func formatted(title: String, text: String) -> NSAttributedString {
    let result = NSMutableAttributedString(string: "")
    func append(_ line: String, size: CGFloat, bold: Bool = false, before: CGFloat = 0) {
      let style = NSMutableParagraphStyle()
      style.lineSpacing = 5
      style.paragraphSpacing = 8
      style.paragraphSpacingBefore = before
      result.append(
        NSAttributedString(
          string: line + "\n",
          attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular),
            .paragraphStyle: style, .foregroundColor: NSColor.black,
          ]))
    }
    append(title, size: 20, bold: true)
    for line in text.components(separatedBy: .newlines) {
      if line.hasPrefix("## ") {
        append(String(line.dropFirst(3)), size: 15, bold: true, before: 12)
      } else if line.hasPrefix("[x] ") || line.hasPrefix("[ ] ") {
        append(
          (line.hasPrefix("[x] ") ? "已完成 · " : "待办 · ") + line.dropFirst(4), size: 14, bold: true,
          before: 10)
      } else if !line.isEmpty {
        append(line, size: 12)
      }
    }
    return result
  }
  static func pdf(title: String, text: String) -> Data {
    let content = formatted(title: title, text: text)
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &box, nil)
    else { return Data() }
    let framesetter = CTFramesetterCreateWithAttributedString(content)
    var cursor = 0
    while cursor < content.length {
      context.beginPDFPage(nil)
      let path = CGPath(rect: box.insetBy(dx: 45, dy: 45), transform: nil)
      let frame = CTFramesetterCreateFrame(
        framesetter, CFRange(location: cursor, length: 0), path, nil)
      let count = CTFrameGetVisibleStringRange(frame).length
      if count == 0 {
        context.endPDFPage()
        break
      }
      CTFrameDraw(frame, context)
      cursor += count
      context.endPDFPage()
    }
    context.closePDF()
    return data as Data
  }
  static func word(title: String, text: String) throws -> Data {
    let attributed = formatted(title: title, text: text)
    return try attributed.data(
      from: NSRange(location: 0, length: attributed.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
  }
  static func exportWord(title: String, text: String) {
    do {
      let data = try word(title: title, text: text)
      let panel = NSSavePanel()
      panel.nameFieldStringValue = filename(title, ext: "docx")
      if panel.runModal() == .OK, let url = panel.url { try data.write(to: url) }
    } catch { NSAlert(error: error).runModal() }
  }
  static func exportPDF(title: String, text: String) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = filename(title, ext: "pdf")
    if panel.runModal() == .OK, let url = panel.url {
      do { try pdf(title: title, text: text).write(to: url) } catch {
        NSAlert(error: error).runModal()
      }
    }
  }
  static func exportBackup(_ doc: VTDocument) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "会议文字备份.json"
    panel.message = "此备份包含原文、图形和历史成果，不包含音频文件或密钥。"
    if panel.runModal() == .OK, let url = panel.url {
      do { try JSONEncoder().encode(doc).write(to: url, options: .atomic) } catch {
        NSAlert(error: error).runModal()
      }
    }
  }
  static func share(_ doc: VTDocument, title: String, text: String) {
    do {
      let url = try shareFile(doc, title: title, text: text)
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } catch { NSAlert(error: error).runModal() }
  }
  static func shareFile(_ doc: VTDocument, title: String, text: String, graph: Bool = false) throws
    -> URL
  {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
      "VoiceTraceShare-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(graph ? "观点图.png" : title + ".pdf")
    try (graph ? graphPNG(doc) : pdf(title: doc.title + " · " + title, text: text)).write(
      to: url, options: .atomic)
    return url
  }
  static func graphPNG(_ doc: VTDocument) throws -> Data {
    let layout = VTLayout.make(doc.analysis.graph)
    guard !layout.items.isEmpty, layout.width * layout.height <= 40_000_000, layout.width < 18000,
      layout.height < 18000
    else { throw VTError.message("图形为空或过大，请使用SVG导出") }
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(layout.width), pixelsHigh: Int(layout.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { throw VTError.message("无法生成图形图片") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: layout.width, height: layout.height)).fill()
    for e in doc.analysis.graph.edges {
      guard let a = layout.items.first(where: { $0.id == e.from }),
        let b = layout.items.first(where: { $0.id == e.to })
      else { continue }
      let x = a.x + a.width
      let y = layout.height - a.y - a.height / 2
      let x2 = b.x
      let y2 = layout.height - b.y - b.height / 2
      let path = NSBezierPath()
      path.lineWidth = 2
      path.move(to: NSPoint(x: x, y: y))
      path.curve(
        to: NSPoint(x: x2, y: y2), controlPoint1: NSPoint(x: x + 45, y: y),
        controlPoint2: NSPoint(x: x2 - 45, y: y2))
      NSColor.systemGray.setStroke()
      path.stroke()
      let arrow = NSBezierPath()
      arrow.move(to: NSPoint(x: x2, y: y2))
      arrow.line(to: NSPoint(x: x2 - 7, y: y2 - 4))
      arrow.line(to: NSPoint(x: x2 - 7, y: y2 + 4))
      arrow.close()
      NSColor.systemGray.setFill()
      arrow.fill()
      NSAttributedString(
        string: e.relation,
        attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.darkGray]
      ).draw(in: NSRect(x: (x + x2) / 2 - 38, y: (y + y2) / 2 + 6, width: 78, height: 16))
    }
    for p in layout.items {
      guard let n = doc.analysis.graph.nodes.first(where: { $0.id == p.id }) else { continue }
      let rect = NSRect(x: p.x, y: layout.height - p.y - p.height, width: p.width, height: p.height)
      NSColor.white.setFill()
      NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11).fill()
      NSColor.lightGray.setStroke()
      NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11).stroke()
      let style = NSMutableParagraphStyle()
      style.lineBreakMode = .byWordWrapping
      let label = NSAttributedString(
        string: n.kind.label + " · " + (n.kind == .topic ? "讨论议题" : doc.speaker(n.speakerID)),
        attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.systemIndigo])
      label.draw(in: NSRect(x: p.x + 17, y: rect.maxY - 31, width: 266, height: 18))
      NSAttributedString(
        string: n.title,
        attributes: [
          .font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.black,
          .paragraphStyle: style,
        ]
      ).draw(in: NSRect(x: p.x + 17, y: rect.maxY - 77, width: 266, height: 40))
      NSAttributedString(
        string: n.detail,
        attributes: [
          .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.darkGray,
          .paragraphStyle: style,
        ]
      ).draw(
        with: NSRect(x: p.x + 17, y: rect.maxY - 132, width: 266, height: 46),
        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
      NSAttributedString(
        string: doc.sources(n.sourceIDs).map { doc.timeLabel($0) }.joined(separator: " · "),
        attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.gray]
      ).draw(in: NSRect(x: p.x + 17, y: rect.minY + 13, width: 266, height: 18))
    }
    context.flushGraphics()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
      throw VTError.message("图片编码失败")
    }
    return data
  }
  static func exportGraph(_ doc: VTDocument) {
    do {
      let data = try graphPNG(doc)
      let panel = NSSavePanel()
      panel.nameFieldStringValue = filename(doc.title + "-观点图", ext: "png")
      if panel.runModal() == .OK, let url = panel.url { try data.write(to: url) }
    } catch { NSAlert(error: error).runModal() }
  }
}

/// 系统分享面板由用户选择目标服务；文件在本机生成，不自动发送。
struct VTFileShareButton: NSViewRepresentable {
  var enabled: Bool
  var file: () throws -> URL
  func makeCoordinator() -> Coordinator { Coordinator(file) }
  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(
      title: "分享", target: context.coordinator, action: #selector(Coordinator.share(_:)))
    button.bezelStyle = .rounded
    button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
    button.imagePosition = .imageLeading
    button.toolTip = "通过系统分享文件；也可下载后拖入微信或钉钉"
    return button
  }
  func updateNSView(_ button: NSButton, context: Context) {
    button.isEnabled = enabled
    context.coordinator.file = file
  }
  @MainActor final class Coordinator: NSObject {
    var file: () throws -> URL
    var picker: NSSharingServicePicker?
    init(_ file: @escaping () throws -> URL) { self.file = file }
    @objc func share(_ sender: NSButton) {
      do {
        picker = NSSharingServicePicker(items: [try file()])
        picker?.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
      } catch { NSAlert(error: error).runModal() }
    }
  }
}
