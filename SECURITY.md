# Security and privacy / 安全与隐私

Please do not include API keys, signing identities, real audio, transcripts, or meeting exports in issues or pull requests. Redact screenshots before reporting a problem.

请勿在Issue或Pull Request中附带API Key、签名证书、真实音频、逐字稿或会议导出文件。报告问题前请遮盖截图中的敏感信息。

## Data boundaries / 数据边界

- Keychain: provider credentials; application preferences: non-secret model profiles.
- Local Documents/VoiceTrace folder: meeting text and audio; not additionally encrypted.
- Cloud speech provider: audio during live or post-meeting recognition.
- Configured text provider: confirmed transcript chunks and intermediate summaries during enabled periodic/final processing, or when the user requests summaries or questions. Periodic summaries (30 seconds) and final summaries are enabled by default and can be disabled independently in Settings → Recording & Summaries.
- System sharing: recipient selection and final sending are controlled by the user.

清洁版默认构建不迁移个人版密钥、偏好设置或会议资料。仓库排除本地数据、构建产物、缓存和常见凭据文件。源码中的可选 PERSONAL_BUILD 兼容分支不含任何密钥或真实Workspace ID，默认构建和CI均不启用。

录音中的定时整理及结束后整理默认开启，可以在“设置→录音与整理”分别关闭。开启时，已确认的逐字稿片段和中间摘要会发送至配置的整理服务商。修订历史、缓存、AI建议及最近删除也属于本机资料；需要额外加密或禁止云同步的用户应自行管理资料目录及系统设置。

## Checks / 检查

Run `python3 scripts/audit.py --staged` before committing and review `git diff --cached` yourself. Enable `.githooks` for repository-local enforcement. Detection is heuristic; it cannot prove the absence of every possible secret.

提交前运行审计并人工检查暂存区。若凭据已泄露，应在服务商处撤销或轮换；仅从当前文件中移除不足以消除已有副本。

For a vulnerability report, use the repository's private reporting channel if the owner enables one. Otherwise open an issue containing only a high-level description and ask the maintainer how to provide sensitive details privately.
