# 更新记录 / Changelog

## 0.13.1 — 2026-10-29

### 中文

- 发布重建后的原生声迹VoiceTrace工作台；默认构建入口切换为独立配置的清洁版。
- 类型化会议成果、SQLite事务与修订、来源校验、真实观点节点和方向关系、独立会议纪要与待办。
- 编号发言人统一改名、最新原文跟随、紫色图标与声波、会议库勾选／重命名／批量移入最近删除。
- 本地录音先启动，后台读取凭据并连接识别；有限重连、音频配置恢复、连续PCM重采样与安全诊断。
- 问答提交立即清空输入框，连续对话保存；未定稿默认收起，可关闭提示而保留原文。
- 各主要页面复制／下载／分享，图形PNG/SVG、文字Word/PDF/Markdown/TXT。
- 更新中英文说明与清洁版虚构会议截图；无个人凭据或真实会议数据。
- 通过离线及模拟验收、通用构建和签名检查；真实设备、长录音与云端质量另行实测。豆包尚未接入。

### English

- Publish the rebuilt native workbench; root builds now default to the isolated clean edition.
- Typed outputs, SQLite transactions/revisions, source validation, actual directed opinion graphs, dedicated minutes and tasks.
- Numbered speaker renaming, transcript follow controls, purple icon/waveform and explicit library selection/rename/trash/restore.
- Local capture before asynchronous credentials/speech connection; bounded reconnection, device recovery, streaming PCM conversion and content-free diagnostics.
- Clear the composer on submit and persist conversation history. Collapse/dismiss unfinished-draft notices without deleting text.
- Page-specific copy/download/share, PNG/SVG graphs and Word/PDF/Markdown/TXT text outputs.
- Refresh bilingual documentation and fictional clean-edition screenshots; no private credentials or real meetings.
- Offline/simulated checks, universal builds and signature verification passed. Physical devices, long recordings and cloud quality still need trials. Doubao is not yet integrated.


## 0.10.0

- 五个整理页面改用结构化节点：纪要分组、可展开观点树、分歧立场对照、章节时间列表及可勾选待办。
- 校验原文时间、发言人标签及任务负责人/期限的文字依据；格式不合格时重试一次，仍不合格则保留旧结果。
- 长会议按原文分段保留节点，避免多轮压缩丢失观点和任务；最终整理使用独立缓存。
- 复制、修订比较及导出同步转换为可读文字，思维链图片保留分层及连接线。
- 原有文字记录仍可打开；重新整理后使用节点视图，人工保护保持生效。
- Structured meeting sections, expandable opinion branches, position comparisons, chapter navigation and persistent task completion.
- Grounded timestamp/speaker checks, bounded format retry, legacy record compatibility and readable exports.

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
