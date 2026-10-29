import AppKit
import SwiftUI

/// 只响应逐字稿区域的真实滚轮事件；程序定位、其他面板滚动不会误关跟随。
struct VTTranscriptScrollObserver: NSViewRepresentable {
  var onUserScroll: () -> Void
  final class Coordinator {
    var monitor: Any?
    var action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    deinit { if let monitor = monitor { NSEvent.removeMonitor(monitor) } }
  }
  func makeCoordinator() -> Coordinator { Coordinator(onUserScroll) }
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
      [weak view, weak coordinator = context.coordinator] event in
      if let view = view, event.window === view.window,
        abs(event.scrollingDeltaY) + abs(event.scrollingDeltaX) > 0.5,
        view.bounds.contains(view.convert(event.locationInWindow, from: nil))
      {
        coordinator?.action()
      }
      return event
    }
    return view
  }
  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.action = onUserScroll
  }
  static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
    if let monitor = coordinator.monitor {
      NSEvent.removeMonitor(monitor)
      coordinator.monitor = nil
    }
  }
}
