import AppKit
import PDFKit

@main struct ExportChecks {
  @MainActor static func main() throws {
    let base = URL(fileURLWithPath: CommandLine.arguments[1])
    let folder = base.appendingPathComponent("outputs/VoiceTrace-0.13-pages")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var doc = VTFixture.source()
    let raw = try String(contentsOf: base.appendingPathComponent("Next/Fixtures/response.json"), encoding: .utf8)
    doc.analysis = try VTAnalyzer.ingest(raw, document: doc, model: "fictional")
    let pages = [("总览", "总览", "原文"), ("原文", "原文", "林悦"), ("观点图", "观点图", "议题"), ("会议纪要", "会议纪要", "电脑端"), ("行动", "待办清单", "周五")]
    for (page, label, expected) in pages {
      let text = doc.pageText(page)
      precondition(text.contains(expected))
      let pdf = VTExporter.pdf(title: doc.title + "-" + label, text: text)
      guard let document = PDFDocument(data: pdf), let read = document.string else { preconditionFailure("PDF无法重开读取") }
      precondition(read.contains(expected) && !read.contains("## "))
      let word = try VTExporter.word(title: doc.title + "-" + label, text: text)
      let reopened = try NSAttributedString(data: word, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
      precondition(reopened.string.contains(expected) && !reopened.string.contains("## "))
      try pdf.write(to: folder.appendingPathComponent(label + ".pdf"))
      try word.write(to: folder.appendingPathComponent(label + ".docx"))
      try text.write(to: folder.appendingPathComponent(label + ".md"), atomically: true, encoding: .utf8)
      let share = try VTExporter.shareFile(doc, title: label, text: text, graph: page == "观点图")
      let bytes = try Data(contentsOf: share)
      if page == "观点图" { precondition(share.pathExtension == "png" && NSBitmapImageRep(data: bytes) != nil) }
      else { precondition(share.pathExtension == "pdf" && PDFDocument(data: bytes)?.string?.contains(expected) == true) }
    }
    precondition(VTExporter.filename("A/B:会议-原文", ext: "pdf") == "A-B-会议-原文.pdf")
    print("PASS: 五个页面的Word/PDF重开读取及内容对应；标题排版；分享文件本地生成（观点图PNG，其余PDF）；下载文件名。未打开分享面板或发送文件。")
  }
}
