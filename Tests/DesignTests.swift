import SwiftUI
import AppKit
@main struct DesignChecks {
 @MainActor static func main(){
  func rgba(_ color:Color)->[Double]{let c=NSColor(color).usingColorSpace(.sRGB)!;return [Double(c.redComponent),Double(c.greenComponent),Double(c.blueComponent),Double(c.alphaComponent)]}
  func over(_ foreground:[Double],_ background:[Double])->[Double]{(0..<3).map{foreground[$0]*foreground[3]+background[$0]*(1-foreground[3])}+[1]}
  func luminance(_ rgb:[Double])->Double{zip(rgb.prefix(3),[0.2126,0.7152,0.0722]).reduce(0){sum,pair in let (c,w)=pair;return sum+w*(c<=0.04045 ? c/12.92:pow((c+0.055)/1.055,2.4))}}
  func ratio(_ a:[Double],_ b:[Double])->Double{let x=luminance(a),y=luminance(b);return(max(x,y)+0.05)/(min(x,y)+0.05)}
  for name in ["燕麦森林","沙色灰蓝","芒果","秋日"]{
   let p=Palette.named(name),paper=rgba(Palette.named(name).paper),side=rgba(Palette.named(name).side)
   precondition(ratio(rgba(p.ink),paper)>=4.5)
   precondition(ratio(over(rgba(p.muted),paper),paper)>=4.5)
   precondition(ratio(rgba(.white),rgba(p.accent))>=4.5)
   let selected=over(rgba(p.accent.opacity(0.075)),side)
   precondition(ratio(rgba(p.actionText),selected)>=4.5)
  }
  precondition(UIGrid.control>=32 && UIGrid.primary>=40)
  print("通过：四主题实际颜色令牌的正文、辅助文字、按钮白字和选中项对比度，以及桌面控件尺寸。")
 }
}
