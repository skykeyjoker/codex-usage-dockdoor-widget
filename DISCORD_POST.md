# Discord sharing draft

## v1.1.0 update reply

Thanks for the detailed feedback — Codex Usage v1.1.0 is now available:

https://github.com/skykeyjoker/codex-usage-dockdoor-widget/releases/tag/v1.1.0

This update focuses on making the widget easier to read and much easier to
tailor to different workflows:

- Added **Simplified**, **Full**, and **Custom** Panel presets. Each content
  page can be hidden, and cards on every page can be shown/hidden and reordered.
- Added Token formatting choices: adaptive, exact, `240.18M`, `240.2M`, or
  `0.24B`.
- Added an optional bottom launcher for **GPT Classic**, **Codex Desktop**, and
  **Codex CLI**. Each button can be enabled independently, and Terminal,
  Ghostty, iTerm2, or Warp can be selected for CLI actions.
- Recent sessions now distinguish Codex Desktop from Codex CLI. Clicking a CLI
  session resumes it in the selected terminal; Desktop sessions still open in
  Codex Desktop.
- Smoothed the hover-metric transition in Projects & Tasks and kept a compact
  metrics HUD visible when the source cards scroll out of view.
- Improved two-/three-slot readability, shared ring styling, chart hover
  feedback, Panel card styling, and numeric typography.
- Regenerated all README screenshots directly from the current SwiftUI code at
  Retina resolution using anonymous fixture data.

Privacy behavior is unchanged: there is no telemetry or custom backend, local
Codex logs stay local, and displayed costs remain API-equivalent estimates —
not subscription billing.

For this reply, attach these updated screenshots in order:

1. `assets/dock-layouts.png`
2. `assets/panel-settings.png`
3. `assets/panel-overview.png`
4. `assets/panel-insights-official.png`
5. `assets/panel-insights-local.png`
6. `assets/panel-conversations.png`
7. `assets/panel-status.png`

---

## Original thread starter draft

## Forum title

**Codex Usage for DockDoor Pro — quota, activity, local analytics, tasks & status**

### Post body

I built an independent Codex Usage widget for DockDoor Pro and am sharing the
source plus a universal Apple Silicon/Intel bundle here:

https://github.com/skykeyjoker/codex-usage-dockdoor-widget

It is not a marketplace widget, so installation is manual from the GitHub
Release. The README includes the exact install path, build instructions,
troubleshooting, data-source notes, and a detailed privacy disclosure.

Highlights:

- 1/2/3-slot Dock layouts with weekly or session quota, used/remaining modes,
  four one-slot ring styles, adaptive themes, and optional service status.
- Overview with quota reset timing, usage pace, reset credits, extra-model
  quotas, and an interactive recent Token/cost chart.
- Official activity with lifetime Tokens, peak day, streaks, an activity
  heatmap, and daily/weekly/cumulative trends.
- Local 7/30-day analytics with Token composition, request/turn counts,
  cache hit, Fast/Priority share, models, projects, and API-equivalent cost.
- Recent projects and conversations/tasks with Codex deep links, context
  health, TTFT, average duration, compactions, and aborted-turn metrics.
- ChatGPT/Codex component status plus a data-health page for every source.
- Automatic English/Chinese UI and light/dark appearance support.

Privacy summary:

- No telemetry, custom backend, or developer-operated server.
- Quota requests go directly to OpenAI using the existing local Codex login, or
  can use the local read-only Codex CLI RPC source.
- Usage/project/task analytics are calculated from local `~/.codex` metadata;
  the widget does not upload local logs.
- Recent conversation titles are read locally for display and are not persisted
  by the widget or uploaded.
- Pricing comes from models.dev with a bundled fallback; status comes from
  status.openai.com.
- Cost is an API-equivalent estimate, not a subscription bill.

Tested on macOS 14+ with DockDoor Pro 1.1.2. The release bundle contains both
`arm64` and `x86_64` slices.

Thanks to @ejbills and the DockDoor Pro community for the widget platform, and
to CodexBar for the MIT-licensed quota/pricing compatibility work.

## Attach these screenshots in this order

Upload the original files without resaving them. They are captured from a
Retina-backed SwiftUI window so Discord can downscale them cleanly.

1. `assets/dock-layouts.png` — one-, two-, and three-slot Dock presentations.
2. `assets/panel-overview.png` — quota overview and recent Token usage.
3. `assets/panel-insights-official.png` — official activity and trends.
4. `assets/panel-insights-local.png` — local usage composition and models.
5. `assets/panel-projects.png` — project usage summaries.
6. `assets/panel-conversations.png` — recent tasks and context health.
7. `assets/panel-status.png` — ChatGPT and Codex service status.
8. `assets/panel-settings.png` — Dock/Panel settings and source health.

Optional ninth screenshot: `assets/panel-overview-dark.png` to show dark mode.
