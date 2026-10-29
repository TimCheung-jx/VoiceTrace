# 安全与隐私 / Security & privacy

请勿在 Issue、Pull Request 或公开截图中附带真实密钥、录音、逐字稿或会议导出文件。报告问题请使用虚构内容或遮盖敏感信息。

Never include real credentials, recordings, transcripts or meeting exports in public issues, pull requests or screenshots. Use fictional or redacted material.

## 当前 0.13.1 / Current 0.13.1

- 清洁版无预置 API Key、Workspace ID 或个人配置；默认构建和CI使用清洁模式。`PERSONAL_BUILD`仅为可选本机兼容分支，不含真实凭据。
- API Key 存于 macOS 钥匙串，读取后在当前进程内缓存，不嵌入安装包、源码或诊断。
- 清洁版会议库为 `~/Library/Application Support/VoiceTrace Next`；个人版使用独立的 `VoiceTrace Next Personal`。内部目录名保留兼容性，界面产品名为声迹VoiceTrace。
- 资料库含音频、原文、笔记、成果、问答、修订及缓存，没有额外加密。最近删除和隐藏的未定稿仍属于本机资料，不会自动永久清除。
- 本地录音先写盘；启用识别向所选语音服务发送音频。整理／提问向文字服务发送相应原文和必要上下文。周期整理默认开启，每45秒检查一次；结束后整理默认开启，两者可在设置分别关闭。
- 启动诊断最多32阶段，只含白名单阶段、相对毫秒数和数字错误码；不含录音、原文、问题、服务配置或密钥。未定稿不进入会议整理的原文输入。
- 系统分享由用户选择服务和发送对象，应用不会自动给联系人发消息。

The clean edition has no embedded keys, Workspace IDs or private profiles, and is the default for public builds and CI. The optional personal compatibility branch contains no real credentials. Keys use macOS Keychain with in-process caching. The clean library is `~/Library/Application Support/VoiceTrace Next`, separate from the personal edition. Local data is not additionally encrypted; Recently Deleted and hidden drafts retain data.

Recognition sends audio to the selected speech provider. Analysis/questions send relevant text and necessary context to the configured text provider. Periodic analysis (checked every 45 seconds) and final analysis are enabled by default, independently configurable. Diagnostic records contain only up to 32 whitelisted technical phases, relative milliseconds and numeric codes. Unfinished drafts are excluded from the meeting-analysis source. Sharing is user-controlled.

## 发布检查 / Publishing checks

```sh
python3 scripts/audit.py --staged
python3 scripts/test_audit.py
```

人工复核暂存区和截图；规则扫描不能证明不存在任何未知形式的秘密。公开仓库排除本地资料、凭据、构建与测试输出。若凭据已泄露，应在服务商撤销或轮换，仅移除当前文件不足以消除既有副本。

Review staged changes and screenshots manually. Detection is heuristic. If a credential leaks, revoke or rotate it at the provider; removing the current file does not remove existing copies.

如报告漏洞，请使用仓库已启用的私人安全报告渠道；没有该渠道时，仅公开高层描述，再向维护者询问安全提供细节的方法。

Use the repository's private vulnerability reporting channel when available. Otherwise share only a high-level public description and ask how to provide sensitive details privately.
