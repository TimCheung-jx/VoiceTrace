import SwiftUI

struct VTGraphView: View {
  @ObservedObject var w: VTWorkspace
  @State private var zoom: Double = 0.8
  @State private var collapsed = Set<String>()
  var graph: VTGraph {
    let full = w.document.analysis.graph
    var keep = Set(full.nodes.map { $0.id })
    if w.onlyDisputes {
      keep = Set(w.document.analysis.disputes.flatMap { $0.positionIDs })
      for _ in 0..<full.nodes.count {
        let old = keep
        for edge in full.edges where keep.contains(edge.to) { keep.insert(edge.from) }
        if old == keep { break }
      }
    }
    if let speaker = w.filterSpeaker {
      var selected = Set(full.nodes.filter { $0.speakerID == speaker }.map { $0.id })
      for _ in 0..<full.nodes.count {
        let old = selected
        for edge in full.edges where selected.contains(edge.to) { selected.insert(edge.from) }
        if old == selected { break }
      }
      keep.formIntersection(selected)
    }
    return VTGraph(
      nodes: full.nodes.filter { keep.contains($0.id) },
      edges: full.edges.filter { keep.contains($0.from) && keep.contains($0.to) })
  }
  private var modePicker: some View {
    Picker("视图", selection: $w.onlyDisputes) {
      Text("完整观点图").tag(false)
      Text("分歧视图").tag(true)
    }.pickerStyle(.segmented).frame(width: 220)
  }
  private var speakerPicker: some View {
    Picker("发言人", selection: $w.filterSpeaker) {
      Text("所有发言人").tag(nil as String?)
      ForEach(w.document.speakers) { s in Text(s.name).tag(Optional(s.id)) }
    }.labelsHidden().frame(width: 135)
  }
  private func zoomControls(_ size: CGSize) -> some View {
    Group {
      Button {
        zoom = max(0.3, zoom - 0.1)
      } label: {
        Image(systemName: "minus.magnifyingglass")
      }.help("缩小")
      Text("\(Int(zoom*100))%").monospacedDigit().font(.caption).frame(width: 38)
      Button {
        zoom = min(1.6, zoom + 0.1)
      } label: {
        Image(systemName: "plus.magnifyingglass")
      }.help("放大")
      Button("适应窗口") {
        let layout = VTLayout.make(graph, collapsed: collapsed)
        zoom = min(
          1, max(0.2, min((size.width - 30) / layout.width, (size.height - 90) / layout.height)))
      }
      Menu {
        Button("展开全部") { collapsed = [] }
        Button("收起议题") { collapsed = Set(graph.nodes.filter { $0.kind == .topic }.map { $0.id }) }
      } label: {
        Image(systemName: "ellipsis")
      }.menuStyle(.borderlessButton).fixedSize()
    }
  }
  var body: some View {
    GeometryReader { geo in
      VStack(spacing: 0) {
        Group {
          if geo.size.width < 720 {
            VStack(spacing: 10) {
              HStack {
                modePicker
                Spacer()
                speakerPicker
              }
              HStack {
                zoomControls(geo.size)
                Spacer()
              }
            }
          } else {
            HStack(spacing: 12) {
              modePicker
              speakerPicker
              Spacer(minLength: 4)
              zoomControls(geo.size)
            }
          }
        }.buttonStyle(.borderless).padding(.horizontal, 18).padding(.vertical, 12).background(
          .background)
        Divider()
        if graph.nodes.isEmpty {
          VTEmpty(
            title: w.onlyDisputes ? "没有可展示的分歧" : "观点图尚未生成",
            detail: w.onlyDisputes ? "没有明确分歧时不会人为制造对立。也可切换完整观点图查看讨论。" : "整理成功后将在此显示议题、观点和关系。",
            symbol: "point.3.connected.trianglepath.dotted")
        } else {
          let layout = VTLayout.make(graph, collapsed: collapsed)
          ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
              ForEach(graph.edges) { edge in
                if let a = layout.items.first(where: { $0.id == edge.from }),
                  let b = layout.items.first(where: { $0.id == edge.to })
                {
                  Path { p in
                    p.move(to: CGPoint(x: a.x + a.width, y: a.y + a.height / 2))
                    p.addCurve(
                      to: CGPoint(x: b.x, y: b.y + b.height / 2),
                      control1: CGPoint(x: a.x + a.width + 45, y: a.y + a.height / 2),
                      control2: CGPoint(x: b.x - 45, y: b.y + b.height / 2))
                  }.stroke(
                    edge.relation.contains("反对")
                      ? Color.orange.opacity(0.65) : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5))
                  Path { p in
                    let x = b.x
                    let y = b.y + b.height / 2
                    p.move(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x - 7, y: y - 4))
                    p.addLine(to: CGPoint(x: x - 7, y: y + 4))
                    p.closeSubpath()
                  }.fill(Color.secondary.opacity(0.5))
                  Text(edge.relation).font(.system(size: 10, weight: .medium)).foregroundStyle(
                    .secondary
                  ).padding(3).background(VTStyle.canvas).position(
                    x: (a.x + a.width + b.x) / 2, y: (a.y + b.y) / 2 + a.height / 2 - 10)
                }
              }
              ForEach(layout.items, id: \.id) { p in
                if let node = graph.nodes.first(where: { $0.id == p.id }) {
                  VTGraphNode(
                    node: node, speaker: w.document.speaker(node.speakerID),
                    time: w.document.sources(node.sourceIDs).first.map { w.document.timeLabel($0) }
                      ?? "",
                    selected: w.selectedNode == node.id, collapsed: collapsed.contains(node.id),
                    hasChildren: graph.edges.contains { $0.from == node.id }
                  ) { w.select(node) }.frame(width: p.width, height: p.height).position(
                    x: p.x + p.width / 2, y: p.y + p.height / 2
                  )
                  .contextMenu {
                    Button(collapsed.contains(node.id) ? "展开分支" : "收起分支") {
                      if collapsed.contains(node.id) {
                        collapsed.remove(node.id)
                      } else {
                        collapsed.insert(node.id)
                      }
                    }
                    Button("查看原文") { w.select(node) }
                  }
                }
              }
            }.frame(width: layout.width, height: layout.height).scaleEffect(
              zoom, anchor: .topLeading
            ).frame(
              width: layout.width * zoom, height: layout.height * zoom, alignment: .topLeading)
          }.background(VTStyle.canvas)
        }
        if w.onlyDisputes && !w.document.analysis.disputes.isEmpty {
          Divider()
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
              ForEach(w.document.analysis.disputes) { d in
                Button {
                  w.reveal(d.sourceIDs)
                } label: {
                  VStack(alignment: .leading, spacing: 5) {
                    Text(d.title).font(.callout.bold())
                    Text(d.category + " · " + d.outcome).font(.caption).lineLimit(2)
                  }.frame(width: 300, alignment: .leading).padding(12).background(VTStyle.soft)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
              }
            }.padding(12)
          }.frame(height: 100)
        }
      }
    }
  }
}
struct VTGraphNode: View {
  let node: VTNode
  let speaker: String
  let time: String
  let selected: Bool
  let collapsed: Bool
  let hasChildren: Bool
  let action: () -> Void
  var color: Color {
    switch node.kind {
    case .topic: return VTStyle.accent
    case .decision: return Color(red: 0.05, green: 0.46, blue: 0.35)
    case .open: return Color(red: 0.65, green: 0.39, blue: 0.04)
    default: return VTStyle.accent.opacity(0.9)
    }
  }
  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text(node.kind.label).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
          Spacer()
          if hasChildren { Text("右键展开/收起").font(.system(size: 9)).foregroundStyle(.secondary) }
        }
        Text(node.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
          .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
        Text(node.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2).frame(
          maxWidth: .infinity, alignment: .leading)
        Spacer(minLength: 0)
        HStack {
          Text(node.speakerID == nil ? (node.kind == .topic ? "讨论议题" : "身份未确认") : speaker)
            .lineLimit(1)
          Spacer()
          Text(time).monospacedDigit()
        }.font(.system(size: 11)).foregroundStyle(.secondary)
      }.padding(17).frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 11)).overlay(
          RoundedRectangle(cornerRadius: 11).stroke(
            selected ? VTStyle.accent : VTStyle.line, lineWidth: selected ? 2 : 1)
        ).overlay(alignment: .leading) {
          RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3).padding(.vertical, 16)
        }
    }.buttonStyle(.plain).accessibilityLabel(
      node.kind.label + "：" + node.title + "，" + speaker + "，点击查看原文")
  }
}
