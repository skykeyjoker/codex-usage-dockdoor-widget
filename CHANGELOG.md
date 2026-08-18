# Changelog

## Unreleased

## 2.0.0 - 2026-08-18

- Added explicit API-equivalent cost coverage and pricing provenance, including
  partial-estimate labels and known-zero versus unavailable semantics.
- Migrated local usage state to an incremental SQLite WAL cache with
  transactional per-file updates, 365-day retention, stable timezone bucketing,
  and live scan progress.
- Made Codex OAuth credentials strictly read-only and hardened app-server RPC
  timeout classification and child-process teardown.
- Added monthly quota-window classification and a Business/Team/EDU/Enterprise
  spend-controls fallback.
- Added All-time local summaries, an hourly activity heatmap, and estimated
  session cost in conversation rows and hover metrics.
- Clarified quota pace by showing “no recent use” for zero short-term movement
  while retaining the full-cycle average rate.
- Increased dark-mode hourly heatmap contrast and normalized intensity against
  the 90th percentile so a single outlier no longer dims every other cell.
- Added pointer-following hourly heatmap details with focused-cell highlighting,
  exact Token and request counts, and automatic edge avoidance.
- Split hourly activity into its own Local usage card, placed between Token
  composition and Top models and independently configurable in Panel settings.
- Limited hourly activity to the current Monday-to-Sunday week, labeled its
  local-log source, and separated hour-axis labels from the heatmap cells.
- Added an optional, cached GitHub Release update monitor to Settings with
  current/latest version status, manual checks, and a direct release link.
- Added a configurable This week / Last year range for hourly activity; both
  the underlying local aggregation and card label switch immediately.
- Enlarged hourly heatmap rows and cells and added extra Sunday-row hit padding
  so pointer hover remains reliable along the bottom edge.
- Added a compact capsule-style header update indicator before the service-status
  dot whenever a newer GitHub Release is available, with hover details and a direct link.
- Added project, author, and contact information to the bottom of Settings, with
  direct GitHub and email actions.
- Pulled hour-axis labels closer to the enlarged heatmap while retaining the
  dedicated Sunday-row pointer hit padding.

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
