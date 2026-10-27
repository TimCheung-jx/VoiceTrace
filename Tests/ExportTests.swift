import Foundation
import AppKit
import PDFKit
@main struct Checks {
 @MainActor static func main() throws {
  let folder=URL(fileURLWithPath:ProcessInfo.processInfo.environment["VOICETRACE_TEST_OUTPUT"] ?? NSTemporaryDirectory()).appendingPathComponent("voicetrace-export-"+UUID().uuidString,isDirectory:true);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  let text=(1...90).map{"[\(String(format:"%02d:00",$0))] 发言人1：这是第\($0)条虚构会议记录。请确认试点范围、负责人和交付日期；未明确的事项保留待确认标记。"}.joined(separator:"\n")
  let sample=ContentSnapshot(meeting:"虚构项目测试会议",section:"转写",body:text)
  precondition(!sample.withTimestamps(false).body.contains("[01:00]"))
  precondition(sample.withTimestamps(true).body==text)
  let plain=try ContentWriter.data(sample,format:.text);precondition(String(data:plain,encoding:.utf8)!.contains("第90条"))
  let pdfData=try ContentWriter.data(sample,format:.pdf);try pdfData.write(to:folder.appendingPathComponent("sample.pdf"));let pdf=PDFDocument(data:pdfData)!
  precondition(pdf.pageCount>1);precondition(pdf.string!.contains("第90条"))
  for i in 0..<pdf.pageCount {let image=pdf.page(at:i)!.thumbnail(of:NSSize(width:800,height:1132),for:.mediaBox);let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!;try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("page-\(i).png"))}
  let word=try ContentWriter.data(sample,format:.word);precondition(word.prefix(2)==Data([0x50,0x4b]));try word.write(to:folder.appendingPathComponent("sample.docx"))
  let back=try NSAttributedString(data:word,options:[.documentType:NSAttributedString.DocumentType.officeOpenXML],documentAttributes:nil);precondition(back.string.contains("第90条"))
  let tree=ContentSnapshot(meeting:"虚构项目测试会议",section:"思维链",body:"试点计划\n  负责人：先开展电脑端试点。[00:00]\n  研发：接口稳定性尚待验证。[01:00]\n交付安排\n  设计：周三提供方案。\n  待确认：正式上线日期与验收指标。")
  let png=try ContentWriter.data(tree,format:.png);try png.write(to:folder.appendingPathComponent("tree.png"));precondition(NSBitmapImageRep(data:png)!.pixelsWide==1200)
  let safe=ContentWriter.filename(ContentSnapshot(meeting:"A/B:C",section:"笔记",body:"x"),format:.text);precondition(!safe.contains("/") && safe.hasSuffix(".txt"))
  do{_=try ContentWriter.data(ContentSnapshot(meeting:"x",section:"笔记",body:""),format:.pdf);preconditionFailure("应拒绝空内容")}catch{}
  print("通过：时间开关、完整文字、多页PDF及末页内容、DOCX往返、思维链PNG、文件名及空内容校验。PDF共\(pdf.pageCount)页。")
 }
}
