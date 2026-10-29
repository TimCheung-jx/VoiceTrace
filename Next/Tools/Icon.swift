import AppKit
// 图形标志由代码绘制，无外部图片及字体依赖。
let size=1024
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
let graphics=NSGraphicsContext(bitmapImageRep:bitmap)!
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=graphics
NSColor(calibratedRed:0.31,green:0.27,blue:0.90,alpha:1).setFill()
NSBezierPath(roundedRect:NSRect(x:24,y:24,width:976,height:976),xRadius:218,yRadius:218).fill()
NSColor.white.setStroke()
for (index,height) in [180.0,330.0,490.0,350.0,205.0].enumerated(){let x=320+Double(index)*96;let path=NSBezierPath();path.lineWidth=43;path.lineCapStyle = .round;path.move(to:NSPoint(x:x,y:512-height/2));path.line(to:NSPoint(x:x,y:512+height/2));path.stroke()}
graphics.flushGraphics();NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
