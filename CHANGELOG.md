# 更新记录 / Changelog

## 0.9.0

### 中文

本次从公开仓库早期版本更新到当前原生 Mac 工作台。

- 录音中同步整理纪要、思维链、分歧点、章节和待办，定时及最终整理可独立开关。
- 长会议采用有界原文分段、缓存复用、分层合并与最终核对，保留分段结果。
- 增加逐字稿纠错、同标签发言人重命名、人工整理页保护、AI建议比较和修订历史恢复。
- 增加全部会议表格、多选删除、最近删除恢复、永久删除确认及批量操作结果。
- 保存会议和整理状态，改进后台保存顺序、退出保护及保存失败提示。
- 检测未登记PCM，支持在本机恢复已写盘部分，保留原件。
- 输入音量来自真实采集；增加设备变化与传输错误处理路径。
- 更新主题令牌、控件和表单、固定保存操作、小窗口助手与原文阅读布局。
- 默认构建为无预置凭据的清洁版；不含任何真实Workspace ID、API Key或会议数据。
- 增加虚构长会议、修订保护、异常写入进程、故障事件、配置隔离和四主题对比度测试。

默认的录音中自动整理与结束后自动整理均开启；可在“设置→录音与整理”关闭。真实服务、真实长录音和物理设备/网络切换仍需使用者单独验证。

### English

This updates the early public release to the current native Mac workspace.

- Concurrent draft summaries, discussion chains, disagreements, chapters, and actions, with independent periodic/final processing switches.
- Bounded transcript chunks, cached work, hierarchical merging, final reconciliation, and retained per-chunk results.
- Transcript corrections, speaker-label updates, protected manual edits, AI suggestion comparison, and revision recovery.
- A meeting table, multi-select deletion, Recently Deleted recovery, confirmed permanent deletion, and partial-failure reporting.
- Persistent session/summary states, ordered background saves, exit protection, and save-failure feedback.
- Local recovery of unregistered PCM recordings while retaining original files.
- Actual microphone level feedback and device-change/transport-error handlers.
- Updated theme tokens, native controls/forms, persistent save actions, compact-window assistant access, and reading layout.
- Clean builds with no embedded credentials, real Workspace IDs, or meeting data.
- Synthetic long-meeting, revision, interrupted-writer, fault-event, profile-isolation, and theme-contrast checks.

Periodic summaries and final summaries are enabled by default and can be disabled independently. Live provider integration, long recordings, and physical device/network changes require separate validation.
