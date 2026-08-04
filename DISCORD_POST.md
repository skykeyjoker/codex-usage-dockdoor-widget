# Discord sharing draft

## Forum title

**Codex Usage for DockDoor Pro — quota, activity, local analytics, tasks & status**

## Post body

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

1. `assets/dock-layouts.png` — one-, two-, and three-slot Dock presentations.
2. `assets/panel-overview.png` — quota overview and recent Token usage.
3. `assets/panel-insights-official.png` — official activity and trends.
4. `assets/panel-insights-local.png` — local usage composition and models.
5. `assets/panel-projects.png` — project usage summaries.
6. `assets/panel-conversations.png` — recent tasks and context health.
7. `assets/panel-status.png` — ChatGPT and Codex service status.
8. `assets/panel-settings.png` — Dock/Panel settings and source health.

Optional ninth screenshot: `assets/panel-overview-dark.png` to show dark mode.
