# VoiceTrace · 声迹

**A native macOS AI meeting workspace: keep the discussion, clarify the differences.**

[简体中文](README.md) · [MIT License](LICENSE) · [Security & privacy](SECURITY.md)

![VoiceTrace workspace with fictional meeting data](docs/images/workspace.png)

## Overview

VoiceTrace is a SwiftUI application that combines cloud speech recognition and language models to turn meetings into transcripts, notes, summaries, discussion chains, disagreement analysis, chapters, and action items. It is designed for reading, checking sources, and replaying important passages.

This is a self-build testing release. Not every provider or supported macOS version has been validated end to end.

## Features

- Live microphone recording and transcription, pause/resume, local audio files, and timestamp playback.
- Optional post-meeting transcription and speaker diarization. Speaker identities across recording segments require review.
- Seven sections: Transcript, Notes, AI Summary, Discussion Chain, Disagreements, Chapters, and Actions.
- **Discussion Chain** structures participants' topics, positions, stated reasons, responses, and conclusions. It is not the model's private chain of thought.
- **Disagreements** distinguishes explicit opposing positions from execution constraints and unresolved information, with source timestamps. It should not invent conflict when none is stated.
- Transcript-grounded questions and configurable model profiles.
- Copy, DOCX/PDF/TXT/Markdown export, a discussion-chain PNG, and macOS sharing.
- Four visual themes, a collapsible assistant, subtle motion, and reduced-motion support.

![Disagreement analysis using fictional meeting data](docs/images/disagreements.png)

## Clean release and privacy

**No author's API keys, Workspace IDs, private profiles, real recordings, or meeting documents are included.** Bring your own provider accounts and credentials; provider charges apply.

- API keys are stored in macOS Keychain and cached in process memory after a successful read. They are not written to source files, preferences, or logs.
- This clean release uses a separate application and Keychain namespace. It does not load the personal edition's credentials, preferences, or meeting directory.
- Meeting files are stored under `~/Documents/VoiceTrace`; non-secret profiles are stored in application preferences. Meeting files are not additionally encrypted.
- Recognition is not fully offline. Starting transcription sends audio to the configured speech provider; summary and question requests send transcript text to the configured language-model provider.
- Messages are not automatically sent to WeChat, DingTalk, or any contact. The user chooses recipients and confirms sharing.
- Screenshots, bundled demos, and tests use fictional data.

## Requirements and build

- macOS 13 or later.
- Xcode Command Line Tools with Swift and a macOS SDK.
- No local language model or third-party Swift package is required.
- Python 3 is also needed for tests and the publishing audit.

From the repository root:

```sh
./测试.command
./构建.command
```

The build creates an Apple Silicon / Intel universal app and applies an ad-hoc local signature:

```text
outputs/声迹 VoiceTrace Clean.app
outputs/VoiceTrace-Mac-0.6.1-Clean.zip
```

Open the app after extracting it or dragging it to Applications. This is not a notarized Developer ID distribution. Configure a stable signing identity and Apple notarization for wider distribution. macOS may require launch approval and microphone permission.

## Provider setup

Open **Settings → Models & Services** and configure speech and text profiles separately.

| Purpose | Currently adapted interfaces |
|---|---|
| Live speech | Alibaba Cloud Model Studio Fun-ASR-Realtime and its versioned models |
| Post-meeting speech / speakers | `fun-asr`, `paraformer-v2`, `qwen-audio-3.0-asr-flash-filetrans` |
| Speech regions | Beijing and Singapore; region, Workspace ID, and key must match |
| Summaries and questions | Official DeepSeek or an HTTPS Chat Completions-compatible endpoint |

Model availability, permissions, and fees depend on the provider account. The speech connection test checks the task handshake only; the text test sends fixed fictional text. Neither replaces a complete recording test.

Typical flow: create a meeting → record → stop → optionally refine speaker labels → summarize → review sources → export/share.

## Limitations

- Captures the default microphone, not system audio.
- A network interruption stops the current segment; automatic reconnection and retransmission are not implemented.
- Post-meeting recognition uses the provider's temporary development/testing upload storage. Replace it for production use.
- Post-meeting upload is limited to two hours and 300 MB per segment. Speaker IDs are not aligned across segments.
- Ad-hoc signatures do not guarantee persistent Keychain authorization across app updates.
- AI output can be wrong. Review important conclusions, sources, and action items.
- Compatible endpoints and model response formats require testing.

## Development and publishing checks

```sh
# Inspect staged files without printing matched secret values
python3 scripts/audit.py --staged

# Enable the repository-local pre-commit audit
git config core.hooksPath .githooks
```

Tests cover the protocol, old meeting formats, summary fields, timestamps, profile isolation, credential caching, exports, and section data routing. They do not use real credentials, microphones, or cloud calls. The audit is heuristic and does not replace manual review.

## License and contributions

Project source and original repository assets are licensed under the [MIT License](LICENSE). Provider terms and Apple platform/SDK terms apply separately; see [third-party notices](THIRD_PARTY_NOTICES.md). Issues and pull requests are welcome. Never include real credentials or private meeting material in contributions.
