import SwiftUI
import AppKit
import CoreText
import PDFKit
struct ContentSnapshot {
 var meeting:String
 var section:String
 var body:String
 var dated:Date=Date()
 var plain:String {meeting+"\n"+section+"\n\n"+body}
 func withTimestamps(_ enabled:Bool)->Self {
  guard !enabled else{return self};var value=self
  value.body=body.replacingOccurrences(of:"\\[\\d{1,3}:\\d{2}(?::\\d{2})?\\]",with:"",options:.regularExpression)
  return value
 }
}
enum DownloadFormat:String,CaseIterable {
 case word="Word (.docx)",pdf="PDF (.pdf)",text="纯文本 (.txt)",markdown="Markdown (.md)",png="思维链图片 (.png)"
 var ext:String {switch self{case .word:return "docx";case .pdf:return "pdf";case .text:return "txt";case .markdown:return "md";case .png:return "png"}}
}
@MainActor enum ContentWriter {
 static func attributed(_ item:ContentSnapshot)->NSAttributedString {
  let result=NSMutableAttributedString(string:"")
  func append(_ text:String,font:NSFont,color:NSColor = NSColor(calibratedWhite:0.16,alpha:1)){let style=NSMutableParagraphStyle();style.lineSpacing=5;style.paragraphSpacing=9;style.lineBreakMode = .byWordWrapping;result.append(NSAttributedString(string:text+"\n",attributes:[.font:font,.foregroundColor:color,.paragraphStyle:style]))}
  append(item.meeting,font:.systemFont(ofSize:23,weight:.semibold),color:NSColor(calibratedRed:0.025,green:0.37,blue:0.27,alpha:1))
  append(item.section,font:.systemFont(ofSize:15,weight:.medium))
  for line in item.body.components(separatedBy:"\n") {
   let t=line.trimmingCharacters(in:.whitespaces)
   if t.hasPrefix("#") {append(t.replacingOccurrences(of:"^#+\\s*",with:"",options:.regularExpression),font:.systemFont(ofSize:17,weight:.semibold))}
   else {append(line,font:.systemFont(ofSize:12))}
  }
  return result
 }
 static func pdf(_ item:ContentSnapshot)->Data {
  let buffer=NSMutableData();var box=CGRect(x:0,y:0,width:595.28,height:841.89)
  guard let consumer=CGDataConsumer(data:buffer as CFMutableData),let context=CGContext(consumer:consumer,mediaBox:&box,nil) else{return Data()}
  let text=attributed(item);let setter=CTFramesetterCreateWithAttributedString(text);var position=0
  while position<text.length {
   context.beginPDFPage(nil)
   let path=CGPath(rect:CGRect(x:48,y:48,width:box.width-96,height:box.height-96),transform:nil)
   let frame=CTFramesetterCreateFrame(setter,CFRange(location:position,length:0),path,nil)
   CTFrameDraw(frame,context);let count=CTFrameGetVisibleStringRange(frame).length
   context.endPDFPage();if count==0{break};position+=count
  }
  context.closePDF();return buffer as Data
 }
 // 使用原生文字排版生成分层观点卡片，保持长文本完整，避免截图截断。
 static func treePNG(_ item:ContentSnapshot) throws -> Data {
  let width:CGFloat=1200,pad:CGFloat=70
  let font=NSFont.systemFont(ofSize:24)
  let titleAttrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:36,weight:.semibold),.foregroundColor:NSColor(calibratedWhite:0.16,alpha:1)]
  let paragraph=NSMutableParagraphStyle();paragraph.lineSpacing=10;paragraph.lineBreakMode = .byWordWrapping
  let attrs:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:NSColor(calibratedWhite:0.16,alpha:1),.paragraphStyle:paragraph]
  let title=NSAttributedString(string:item.meeting+" · 思维链",attributes:titleAttrs)
  let titleHeight=ceil(title.boundingRect(with:NSSize(width:width-pad*2,height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading]).height)+20
  let rows=item.body.components(separatedBy:"\n").filter{!$0.trimmingCharacters(in:.whitespaces).isEmpty}.map {line -> (NSAttributedString,CGFloat,CGFloat) in
   let leading=line.prefix{ $0==" " || $0=="\t" }.count
   let indent=min(CGFloat(leading)*10,180)
   let text=NSAttributedString(string:line.trimmingCharacters(in:.whitespaces),attributes:attrs)
   let height=ceil(text.boundingRect(with:NSSize(width:width-pad*2-indent-48,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading]).height)+40
   return (text,height,indent)
  }
  let height=pad*2+titleHeight+rows.reduce(CGFloat(0)){$0+$1.1+20}
  guard height<=20000 else{throw AppError("思维链过长，请改用多页PDF导出，确保内容完整")}
  guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(width),pixelsHigh:Int(height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let graphics=NSGraphicsContext(bitmapImageRep:bitmap) else{throw AppError("无法生成思维链图片")}
  NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=graphics
  NSColor(calibratedRed:0.984,green:0.984,blue:0.98,alpha:1).setFill();NSBezierPath(rect:NSRect(x:0,y:0,width:width,height:height)).fill()
  title.draw(with:NSRect(x:pad,y:height-pad-titleHeight,width:width-pad*2,height:titleHeight),options:[.usesLineFragmentOrigin,.usesFontLeading])
  var top=height-pad-titleHeight
  for (text,h,indent) in rows {
   let rect=NSRect(x:pad+indent,y:top-h,width:width-pad*2-indent,height:h)
   NSColor(calibratedRed:0.91,green:0.94,blue:0.91,alpha:1).setFill();NSBezierPath(roundedRect:rect,xRadius:14,yRadius:14).fill()
   text.draw(with:rect.insetBy(dx:24,dy:20),options:[.usesLineFragmentOrigin,.usesFontLeading]);top-=h+20
  }
  graphics.flushGraphics();NSGraphicsContext.restoreGraphicsState()
  guard let data=bitmap.representation(using:.png,properties:[:]) else{throw AppError("图片编码失败")};return data
 }
 static func data(_ item:ContentSnapshot,format:DownloadFormat) throws -> Data {
  guard !item.body.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{throw AppError("当前页面暂无可导出的内容")}
  switch format {
  case .text:return Data(item.plain.utf8)
  case .markdown:return Data(("# "+item.meeting+"\n\n## "+item.section+"\n\n"+item.body).utf8)
  case .pdf:let data=pdf(item);guard !data.isEmpty else{throw AppError("PDF生成失败")};return data
  case .word:let text=attributed(item);return try text.data(from:NSRange(location:0,length:text.length),documentAttributes:[.documentType:NSAttributedString.DocumentType.officeOpenXML])
  case .png:return try treePNG(item)
  }
 }
 static func filename(_ item:ContentSnapshot,format:DownloadFormat)->String {
  let raw=item.meeting+"-"+item.section
  let safe=raw.components(separatedBy:CharacterSet(charactersIn:"/:\\\n\r\t")).joined(separator:"-")
  return String(safe.prefix(100))+"."+format.ext
 }
}
struct NativeShareButton:NSViewRepresentable {
 var title:String
 var items:()->[Any]
 func makeCoordinator()->Coordinator{Coordinator(items:items)}
 func makeNSView(context:Context)->NSButton{let b=NSButton(title:title,target:context.coordinator,action:#selector(Coordinator.share(_:)));b.bezelStyle = .rounded;return b}
 func updateNSView(_ view:NSButton,context:Context){view.title=title;context.coordinator.items=items}
 final class Coordinator:NSObject {
  var items:()->[Any]
  init(items:@escaping()->[Any]){self.items=items}
  @objc func share(_ sender:NSButton){let content=items();guard !content.isEmpty else{return};let picker=NSSharingServicePicker(items:content);picker.show(relativeTo:sender.bounds,of:sender,preferredEdge:.minY)}
 }
}
extension Workspace {
 var sectionSnapshot:ContentSnapshot {
  let body:String
  switch tab {
  case "转写":body=transcript
  case "笔记":body=meeting.notes
  case "AI纪要":body=meeting.summary
  case "思维链":body=meeting.tree
  case "分歧点":body=meeting.disagreements ?? ""
  case "章节":body=meeting.chapters
  default:body=meeting.todos
  }
  return ContentSnapshot(meeting:meeting.title,section:tab,body:body)
 }
 func copySection(timestamps:Bool) {
  let item=sectionSnapshot.withTimestamps(timestamps)
  guard !item.body.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{alert="当前页面暂无可复制的内容";return}
  NSPasteboard.general.clearContents();NSPasteboard.general.setString(item.plain,forType:.string);status="已复制"+item.section
 }
 func downloadSection(_ format:DownloadFormat,timestamps:Bool) {
  let item=sectionSnapshot.withTimestamps(timestamps)
  do {let data=try ContentWriter.data(item,format:format);let panel=NSSavePanel();panel.nameFieldStringValue=ContentWriter.filename(item,format:format)
   guard panel.runModal() == .OK,let url=panel.url else{return};try data.write(to:url,options:.atomic);status="已导出"+item.section
  }catch{report(error)}
 }
 func shareItems(file:Bool,timestamps:Bool)->[Any] {
  let item=sectionSnapshot.withTimestamps(timestamps)
  guard !item.body.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{alert="当前页面暂无可分享的内容";return []}
  if !file{return [item.plain]}
  do {
   let dir=root.appendingPathComponent("分享导出",isDirectory:true).appendingPathComponent(UUID().uuidString,isDirectory:true)
   try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
   let url=dir.appendingPathComponent(ContentWriter.filename(item,format:.pdf));try ContentWriter.data(item,format:.pdf).write(to:url,options:.atomic)
   return [url]
  }catch{report(error);return []}
 }
 func revealShareFile(timestamps:Bool){guard let url=shareItems(file:true,timestamps:timestamps).first as? URL else{return};NSWorkspace.shared.activateFileViewerSelecting([url]);status="已显示PDF文件，可拖入微信或钉钉聊天窗口"}
}
