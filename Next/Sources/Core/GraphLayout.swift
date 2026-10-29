import Foundation

struct VTPlacement: Equatable {
  var id: String
  var x: Double
  var y: Double
  var width = 300.0
  var height = 172.0
}
struct VTLayout {
  var items: [VTPlacement]
  var width: Double
  var height: Double
  static func make(_ graph: VTGraph, collapsed: Set<String> = []) -> Self {
    let incoming = Set(graph.edges.map { $0.to })
    var roots = graph.nodes.filter { !incoming.contains($0.id) }.map { $0.id }
    if roots.isEmpty { roots = graph.nodes.prefix(1).map { $0.id } }
    var placed: [VTPlacement] = []
    var seen = Set<String>()
    var cursor = 60.0
    func visit(_ id: String, _ depth: Int) -> Double {
      if seen.contains(id) { return placed.first { $0.id == id }?.y ?? cursor }
      seen.insert(id)
      let children =
        collapsed.contains(id)
        ? [] : graph.edges.filter { $0.from == id }.map { $0.to }.filter { !seen.contains($0) }
      let start = cursor
      var positions: [Double] = []
      for child in children { positions.append(visit(child, depth + 1)) }
      let y: Double
      if positions.isEmpty {
        y = cursor
        cursor += 216
      } else {
        y = (positions.first! + positions.last!) / 2
      }
      placed.append(VTPlacement(id: id, x: 60 + Double(depth) * 380, y: max(start, y)))
      return y
    }
    for root in roots {
      _ = visit(root, 0)
      cursor += 40
    }
    return Self(
      items: placed, width: (placed.map { $0.x + $0.width }.max() ?? 600) + 60,
      height: (placed.map { $0.y + $0.height }.max() ?? 300) + 60)
  }
  func svg(_ document: VTDocument) -> String {
    func escape(_ text: String) -> String {
      text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    var body =
      "<defs><marker id='arrow' viewBox='0 0 10 10' refX='9' refY='5' markerWidth='6' markerHeight='6' orient='auto-start-reverse'><path d='M 0 0 L 10 5 L 0 10 z' fill='#98A2B3'/></marker></defs><rect width='100%' height='100%' fill='#F7F8FA'/>"
    for e in document.analysis.graph.edges {
      guard let a = items.first(where: { $0.id == e.from }),
        let b = items.first(where: { $0.id == e.to })
      else { continue }
      let x = a.x + a.width
      let y = a.y + a.height / 2
      let x2 = b.x
      let y2 = b.y + b.height / 2
      body +=
        "<path d='M \(x) \(y) C \(x+40) \(y), \(x2-40) \(y2), \(x2) \(y2)' fill='none' stroke='#98A2B3' stroke-width='2' marker-end='url(#arrow)'/>"
      body +=
        "<text x='\((x+x2)/2)' y='\((y+y2)/2-8)' text-anchor='middle' fill='#667085' font-size='10'>\(escape(e.relation))</text>"
    }
    for p in items {
      guard let n = document.analysis.graph.nodes.first(where: { $0.id == p.id }) else { continue }
      body +=
        "<g><title>\(escape(n.detail))</title><rect x='\(p.x)' y='\(p.y)' width='300' height='172' rx='12' fill='white' stroke='#D0D5DD'/><text x='\(p.x+18)' y='\(p.y+28)' fill='#4F46E5' font-size='12'>\(n.kind.label) · \(escape(n.kind == .topic ? "讨论议题":document.speaker(n.speakerID)))</text>"
      let text = n.title + "｜" + n.detail
      let chars = Array(text)
      for i in 0..<min(4, (chars.count + 17) / 18) {
        let line = String(chars[i * 18..<min(chars.count, (i + 1) * 18)])
        body +=
          "<text x='\(p.x+18)' y='\(p.y+55+Double(i)*23)' fill='#20242B' font-size='14'>\(escape(line))</text>"
      }
      body +=
        "<text x='\(p.x+18)' y='\(p.y+154)' fill='#667085' font-size='12'>\(document.sources(n.sourceIDs).map{document.timeLabel($0)}.joined(separator:" · "))</text></g>"
    }
    return
      "<svg xmlns='http://www.w3.org/2000/svg' width='\(Int(width))' height='\(Int(height))' viewBox='0 0 \(width) \(height)' font-family='PingFang SC, sans-serif'>"
      + body + "</svg>"
  }
}
