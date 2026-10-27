# Security and privacy / 安全与隐私

Please do not include API keys, signing identities, real audio, transcripts, or meeting exports in issues or pull requests. Redact screenshots before reporting a problem.

请勿在Issue或Pull Request中附带API Key、签名证书、真实音频、逐字稿或会议导出文件。报告问题前请遮盖截图中的敏感信息。

## Data boundaries / 数据边界

- Keychain: provider credentials; application preferences: non-secret model profiles.
- Local Documents/VoiceTrace folder: meeting text and audio; not additionally encrypted.
- Cloud speech provider: audio during live or post-meeting recognition.
- Configured text provider: transcript text when the user requests summaries or questions.
- System sharing: recipient selection and final sending are controlled by the user.

清洁版不迁移个人版密钥、偏好设置或会议资料。仓库排除本地数据、构建产物、缓存和常见凭据文件。

## Checks / 检查

Run `python3 scripts/audit.py --staged` before committing and review `git diff --cached` yourself. Enable `.githooks` for repository-local enforcement. Detection is heuristic; it cannot prove the absence of every possible secret.

提交前运行审计并人工检查暂存区。若凭据已泄露，应在服务商处撤销或轮换；仅从当前文件中移除不足以消除已有副本。

For a vulnerability report, use the repository's private reporting channel if the owner enables one. Otherwise open an issue containing only a high-level description and ask the maintainer how to provide sensitive details privately.
