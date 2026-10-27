import SwiftUI
struct Palette {
 var paper:Color;var side:Color;var hero:Color;var accent:Color;var ink:Color
 static func hex(_ s:String)->Color {let v=UInt64(s,radix:16) ?? 0;return Color(red:Double((v>>16)&255)/255,green:Double((v>>8)&255)/255,blue:Double(v&255)/255)}
 static func named(_ name:String)->Palette {
  let values:[String]
  switch name {case "沙色灰蓝":values=["FAF7F4","F1E9E3","DCC1B0","536F80","3D313F"];case "芒果":values=["FCFCF5","F3F4E8","FFE083","2B3C1A","171516"];case "秋日":values=["FCFAF7","F0F2E5","FEC6AD","6B7D36","1F1F29"];default:values=["FBFBFA","F1F2EE","ECEFE7","065F46","2B2D2C"]}
  return Palette(paper:hex(values[0]),side:hex(values[1]),hero:hex(values[2]),accent:hex(values[3]),ink:hex(values[4]))
 }
}
struct QuietButton:ButtonStyle {
 var prominent=false
 var tint:Color=Palette.named("燕麦森林").accent
 func makeBody(configuration:Configuration)->some View {
  configuration.label.font(.system(size:13,weight:prominent ? .semibold:.regular))
   .padding(.horizontal,13).padding(.vertical,9)
   .foregroundStyle(prominent ? .white:tint)
   .background(prominent ? tint:tint.opacity(configuration.isPressed ? 0.12:0))
   .clipShape(RoundedRectangle(cornerRadius:8))
   .opacity(configuration.isPressed ? 0.8:1)
 }
}
