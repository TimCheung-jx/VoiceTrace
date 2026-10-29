# VoiceTrace 0.13.1 native interface

The current application is built from `Next/`. The name visible to users is **声迹VoiceTrace**; the directory name is an internal compatibility detail.

## Current direction

A native, source-centered Mac workspace with system light/dark appearance and a purple action accent. System fonts, compact toolbars, and a separate inspector keep transcript reading and relationship exploration central. The older forest palette described below belongs to the legacy interface, which is no longer built by the default command.

- Navigation: Overview, Transcript, Opinion Graph, Meeting Minutes, To-do List, and Notes. Chapters are available in context; disagreement filtering is part of the graph.
- Graphs use typed nodes, directed edges, relationship labels, deterministic layout, source references, zoom, filters, and branch collapse. Model-generated text is never executed as markup.
- Recording shows a waveform, input level, recognition state and time since the last result. Pause and Finish remain separate controls. Device failures and recognition failures are reported separately.
- A single dismissible draft-count notice replaces repeated unfinished-text cards. An independent bounded sheet preserves access to all drafts.
- Conversation uses distinct user and assistant messages. Submission clears the composer immediately; new typing survives arriving answers.
- Copy, download and share controls remain visible for the current page. Native sharing opens a user-controlled picker.
- The meeting library has explicit checkboxes, Select All, rename, Recently Deleted and restore.
- System reduced-motion settings are respected. Device behavior and complex-graph usability still require user evaluation.

See [acceptance evidence](../Next/docs/ACCEPTANCE.md) for the distinction between simulated checks and device/cloud validation.

## Historical interface notes (0.9–0.10)

# VoiceTrace 0.9 native design system

## Direction

A quiet, content-first Mac meeting notebook. Preserve the approved oatmeal and forest identity; make recording state and source-backed notes the focal points. No landing-page hero, decorative graphs or repeated status banners.

```
Sidebar             Meeting title                     Record / Pause / End
New meeting         Playback + speech / AI status
All meetings        Transcript | Notes | Minutes | Discussion | Disagreements ...
Search              Update / Edit                          Copy / Export / Share
Recent meetings     Readable document                  Collapsible assistant
Settings            Save / error feedback
```

## Tokens

- Paper #FBFBFA, sidebar #F1F2EE, accent #065F46, text #2B2D2C, surface white.
- Font roles: native PingFang for Chinese and SF Pro for Latin. Title 25, section 21, body 15 with 6pt line spacing, controls 13, metadata 12.
- Spacing: 4/8/12/16/24. Main gutter 24. Control height 34, primary 40. Control radius 8, panel radius 12.
- One prominent recording action per meeting. Destructive actions use a distinct red label, icon and explicit confirmation.
- Secondary text uses semantic muted ink. Optional themes use darker action-text roles where the original accent is too light on tinted surfaces; original primary fills are retained.
- At widths below 1180pt, the assistant opens as a sheet. Minimum supported window is 960×640. Recording controls remain visible in the meeting library.
- No network fonts or UI frameworks are added. All interactive primitives remain SwiftUI/AppKit controls.

## Component mapping

| Guidance | Native implementation |
| --- | --- |
| frontend-design: subject-led identity, restraint | Recording-first header; document reading measure; approved forest palette |
| shadcn/ui: semantic roles, modular fields, named dialogs | Palette, QuietButton, FormField, DialogTitle; persistent labels and inline validation |
| daisyUI: base surfaces, primary/content roles, button variants | paper/side/surface; primary/outlined/quiet states; native sheets with visible action rows |
| UI/UX Pro Max: hierarchy, contrast, focus and reduced motion | 12pt minimum metadata, tested color roles, focus outline, native keyboard shortcuts |
| design-review: observed Before/After/Why | Screenshot review in release notes; findings cite Nielsen heuristics and contrast calculations |

## Skill sources

- https://github.com/anthropics/skills/tree/main/skills/frontend-design
- https://github.com/shadcn-ui/ui/tree/main/skills/shadcn
- https://github.com/saadeghi/daisyui/tree/master/skills/daisyui
- UI/UX Pro Max: existing local SKILL.md and its SwiftUI/UX reference database.
- https://github.com/humbleteam/design-review

Web-specific CLIs, Tailwind and React components are not applied to the SwiftUI project. The shadcn and daisyUI skills supply reference rules, not runtime dependencies. iOS-device-specific review is not claimed for a Mac application.


## 0.10 structured meeting pages

Keep the oatmeal/forest theme and existing Mac navigation. Replace the generic paragraph renderer with section-specific native views. The opinion tree uses a topic header, a left trunk, branch connectors and speaker-labelled viewpoint nodes. Disagreements use equal-width position cards plus an outcome section; conditions and uncertainty remain separately labelled. Chapters use time pills and optional descriptions. Tasks expose completion, attribution, deadline and source on separate lines.

Legacy paragraphs remain readable without inventing structure. AI output must carry typed nodes and existing timestamps; unknown speaker identity stays unknown. These checks validate shape and literal references, not the truth of every model interpretation. All development fixtures and visual checks use fictional meetings.
