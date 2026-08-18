# Changelog

## 1.1.2 - 2026-08-18

- Enlarged the one-slot quota ring to match the shared Dock widget footprint.
- Repositioned the one-slot service-status dot against the ring edge and
  replaced its bright white border with a subtle adaptive outline.
- Regenerated the Dock layout screenshots from the updated SwiftUI source.

## 1.1.1 - 2026-08-11

- Increased the horizontal separation between the quota ring and its adjacent
  metrics in two- and three-slot Dock layouts for clearer visual grouping.

## 1.1.0 - 2026-08-05

- Added Simplified, Full, and Custom Panel-content presets.
- Added per-page visibility and per-card visibility/order controls while
  preserving required status, loading, error, and settings surfaces.
- Added configurable Token-number formatting: adaptive, exact, fixed millions,
  and fixed billions.
- Added an optional bottom launcher for GPT Classic, Codex Desktop, and Codex
  CLI, including per-button visibility and terminal selection.
- Added CLI/Desktop conversation-origin detection and terminal-based
  `codex resume` for CLI conversations.
- Smoothed conversation hover-metric transitions and kept a compact metrics HUD
  visible while scrolling the conversation list.
- Improved one-, two-, and three-slot Dock layouts, shared ring styling, Panel
  card backgrounds, chart hover behavior, and Token typography.
- Added explicit three-slot metadata to the bundle and installer registration.
- Regenerated every README screenshot from the current SwiftUI implementation
  at Retina resolution with anonymous fixture data.

## 1.0.0 - 2026-08-04

- Initial standalone release of the local Codex Usage widget.
- One-, two-, and three-slot Dock presentations.
- Session and weekly quota, reset credits, extra-model quotas, and pace hints.
- Recent local Token/cost estimates with models.dev pricing and built-in fallback.
- Official Codex activity, local usage insights, project/task views, and context health.
- OpenAI ChatGPT/Codex service-status page.
- Automatic Chinese/English UI and light/dark appearance support.
