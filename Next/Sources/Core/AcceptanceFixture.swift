import Foundation

// 虚构会议原文。验收时仍须经 API 响应解包、解析、存储再进入视图。
enum VTFixture {
  static func source() -> VTDocument {
    var d = VTDocument()
    d.title = "首轮试点评审 · 虚构验收会议"
    d.speakers = [
      VTSpeaker(id: "lin", name: "林悦"), VTSpeaker(id: "zhou", name: "周衡"),
      VTSpeaker(id: "chen", name: "陈宁"),
    ]
    d.utterances = [
      VTUtterance(id: "u1", start: 0, end: 24, speakerID: "lin", text: "建议第一轮电脑和手机一起试，了解跨设备使用情况。"),
      VTUtterance(
        id: "u2", start: 26, end: 57, speakerID: "zhou", text: "我反对同时铺开。同步能力还没验证，先做电脑端试点。"),
      VTUtterance(id: "u3", start: 61, end: 81, speakerID: "chen", text: "决定先做电脑端。手机端等验证结果后再确定范围。"),
      VTUtterance(
        id: "u4", start: 88, end: 111, speakerID: "zhou", text: "我周五提交同步验证报告。现在不能承诺正式上线日期。"),
      VTUtterance(id: "u5", start: 116, end: 126, speakerID: nil, text: "验收指标是什么？"),
      VTUtterance(id: "u6", start: 129, end: 152, speakerID: "lin", text: "我周三提供验收标准草案。具体指标下次确认。"),
    ]
    return d
  }
  static func envelope(_ content: String, finish: String = "stop") throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "choices": [["finish_reason": finish, "message": ["role": "assistant", "content": content]]]
    ])
  }
}
