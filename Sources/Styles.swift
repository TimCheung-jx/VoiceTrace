import SwiftUI
struct Palette {
 var paper:Color;var side:Color;var hero:Color;var accent:Color;var ink:Color;var actionText:Color
 var surface:Color{.white}
 var muted:Color{ink.opacity(0.72)}
 var border:Color{ink.opacity(0.15)}
 var danger:Color{Self.hex("B42318")}
 var warning:Color{Self.hex("855B17")}
 static func hex(_ s:String)->Color {let v=UInt64(s,radix:16) ?? 0;return Color(red:Double((v>>16)&255)/255,green:Double((v>>8)&255)/255,blue:Double(v&255)/255)}
 static func named(_ name:String)->Palette {
  let values:[String]
  switch name {case "沙色灰蓝":values=["FAF7F4","F1E9E3","DCC1B0","536F80","3D313F"];case "芒果":values=["FCFCF5","F3F4E8","FFE083","2B3C1A","171516"];case "秋日":values=["FCFAF7","F0F2E5","FEC6AD","6B7D36","1F1F29"];default:values=["FBFBFA","F1F2EE","ECEFE7","065F46","2B2D2C"]}
  return Palette(paper:hex(values[0]),side:hex(values[1]),hero:hex(values[2]),accent:hex(values[3]),ink:hex(values[4]),actionText:hex(name=="秋日" ? "4D5F22":name=="沙色灰蓝" ? "3E5B6B":values[3]))
 }
}
enum UIGrid {
 static let gutter:CGFloat=24
 static let control:CGFloat=34
 static let primary:CGFloat=40
 static let radius:CGFloat=8
 static let panel:CGFloat=12
}
struct QuietButton:ButtonStyle {
 var prominent=false
 var tint:Color=Palette.named("燕麦森林").accent
 var outlined=false
 func makeBody(configuration:Configuration)->some View {ButtonSurface(configuration:configuration,prominent:prominent,tint:tint,outlined:outlined)}
}
private struct ButtonSurface:View {
 let configuration:ButtonStyleConfiguration
 let prominent:Bool
 let tint:Color
 let outlined:Bool
 @Environment(\.isEnabled) private var enabled
 @Environment(\.isFocused) private var focused
 @Environment(\.accessibilityReduceMotion) private var reduceMotion
 @State private var hovered=false
 var body:some View {
  configuration.label.font(.system(size:13,weight:prominent ? .semibold:.medium))
   .padding(.horizontal,12).frame(minHeight:prominent ? UIGrid.primary:UIGrid.control)
   .foregroundStyle(prominent ? Color.white:tint)
   .background(prominent ? tint:tint.opacity(configuration.isPressed ? 0.12:hovered ? 0.07:outlined ? 0.035:0))
   .clipShape(RoundedRectangle(cornerRadius:UIGrid.radius))
   .overlay(RoundedRectangle(cornerRadius:UIGrid.radius).strokeBorder(focused ? tint:outlined ? tint.opacity(0.28):.clear,lineWidth:focused ? 2:1))
   .scaleEffect(configuration.isPressed ? 0.99:1)
   .opacity(enabled ? 1:0.42).contentShape(RoundedRectangle(cornerRadius:UIGrid.radius))
   .onHover{hovered=$0}.animation(reduceMotion ? nil:.easeOut(duration:0.12),value:hovered)
 }
}
struct StatusBadge:View {
 let text:String
 let symbol:String
 let tint:Color
 var body:some View{Label(text,systemImage:symbol).font(.system(size:12,weight:.medium)).padding(.horizontal,9).padding(.vertical,5).foregroundStyle(tint).background(tint.opacity(0.065)).clipShape(Capsule()).fixedSize(horizontal:false,vertical:true)}
}
struct FormField<Content:View>:View {
 let title:String
 var hint:String?=nil
 @ViewBuilder var content:()->Content
 var body:some View{VStack(alignment:.leading,spacing:7){Text(title).font(.system(size:13,weight:.medium));content();if let hint=hint{Text(hint).font(.system(size:12)).foregroundStyle(Color.primary.opacity(0.72)).fixedSize(horizontal:false,vertical:true)}}}
}
struct DialogTitle:View {
 let title:String
 let subtitle:String
 var body:some View{VStack(alignment:.leading,spacing:8){Text(title).font(.system(size:22,weight:.semibold));Text(subtitle).font(.system(size:13)).foregroundStyle(Color.primary.opacity(0.72)).fixedSize(horizontal:false,vertical:true)}.frame(maxWidth:.infinity,alignment:.leading)}
}
