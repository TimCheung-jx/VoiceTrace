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
