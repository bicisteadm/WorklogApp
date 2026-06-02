# WorklogApp

A macOS time-tracking app for project/iteration/ticket worklogs, with optional Jira integration. SwiftUI + SwiftData. Lives in the menu bar but launches as a normal Dock app — the window collapses to a menu-bar-only mode when you close it.

## Features

- **Hybrid menu-bar/Dock app** — launches with the main window visible (Dock icon); close the window and only the menu-bar item remains, app keeps running. Reopen from the menu bar.
- **Live timer in the menu bar** — start/stop/pause from either the menu bar dropdown or the main window. Elapsed time displays in `Xh Ymin Zs` format and updates once per second.
- **Projects → Iterations → Tickets → Time entries** — four-level hierarchy. Iterations are typed as sprint or milestone; archived iterations are soft-hidden, not deleted.
- **Inline ticket editing** — edit ticket fields directly in the detail view, no separate edit sheet.
- **Time-entry editing** — change hours/minutes/seconds and notes after the fact.
- **Reports window** (opens as its own NSWindow):
  - Grouping: individual entries / by ticket / by iteration / by project
  - Filters: project, iteration, text search (ticket name / ID / note)
  - Date range filters — separate ranges for *entry date* (`loggedAt`) and *ticket date* (`startDate`), each with `From` / `To` and quick presets (Last 7 days, This month)
  - Columns surface ticket ID prominently + date & time
- **Jira import** (per-project JQL → tickets + sprints) — internal-Jira friendly: uses an embedded `WKWebView` with the user's authenticated session cookies (mTLS supported), no REST tokens needed. Imported tickets are read-only in the UI and refresh on next sync. Reconcile pass deletes imported tickets that fall out of the JQL — or, if they have logged time, keeps them as orphans so worklog data is never lost.
- **Database backup / restore** — export/import the SwiftData SQLite file from the sidebar menu.
- **Daily summary inspector** — collapsible side panel with today's totals.

## Requirements

- macOS 14.0+
- Xcode 15.0+
- Swift 5.9+

## Build & install

The `Makefile` wraps `xcodebuild` with ad-hoc signing flags. Prefer it over raw `xcodebuild`:

```bash
make              # Release build + install to /Applications
make build        # Release build only
make run          # Release build + launch
make test         # Run unit tests
make clean        # Remove DerivedData

# Side-by-side dev instance (separate bundle ID, separate SQLite, orange "DEV" badge)
make debug        # Debug build only (produces WorklogApp-Dev.app)
make dev-run      # Debug build + launch dev instance
make dev-install  # Copy WorklogApp-Dev.app to /Applications
```

Or open `WorklogApp.xcodeproj` in Xcode and hit ⌘R.

## Usage

### First launch

The main window opens with the sidebar. Create a project, add iterations and tickets, start the timer. Closing the window with the red traffic light leaves only the menu-bar icon — click it to reopen.

### Tracking time

1. Pick a ticket in the list
2. Hit "Start Timer" in the detail view, or use the menu-bar dropdown
3. Stop the timer to save a `TimeEntry` (or pause/resume freely)
4. The elapsed time is shown in the menu bar while running

### Jira sync (optional)

1. Right-click a project → "Edit" → paste a JQL into the *Jira sync* field
2. Authenticate once: Settings → Jira → "Connect" opens an embedded browser; sign in the same way you would in Safari (SSO / mTLS / cookies)
3. Right-click the project → "Sync from Jira" — issues become read-only tickets, sprints become iterations, closed sprints are auto-archived

If you later narrow the JQL, the next sync deletes imported tickets that no longer match (or keeps them as orphans when they carry logged time). The edit dialog warns inline when you change the JQL of a synced project.

### Reports

Click "Reports" in the sidebar — opens as its own window. Pick a grouping mode, narrow by project/iteration/text, and optionally apply date-range filters via the *Date filters* button.

### Database backup

Sidebar menu → *Export Database* writes the live SQLite file to a location you pick. *Import Database* replaces the current DB (a `WorklogApp_old.sqlite` backup is kept beside it). Restart required after import.

## Architecture

- **SwiftUI** scenes: `MenuBarExtra` + `WindowGroup` (main) + standalone `Window` scenes for Reports and Jira login + the `Settings` scene
- **SwiftData** for persistence — `ModelContainer` constructed in `WorklogAppApp.init()` with an explicit URL at `~/Library/Application Support/WorklogApp.sqlite` (Debug builds use `WorklogApp-Dev.sqlite`)
- **AppDelegate** owns the activation policy state machine — `.regular` while the window is open, flips to `.accessory` via `applicationShouldTerminateAfterLastWindowClosed` when the last window closes
- **Single shared `TimerState`** (`@StateObject` on the App) passed explicitly to menu bar and main window
- **Jira bridge** runs REST calls from inside a retained `WKWebView` via `callAsyncJavaScript(fetch(…))` so requests carry the user's cookies / mTLS / F5 headers — there is no `URLSession`-based path

See `CLAUDE.md` for the model relationships, the Jira integration constraints, and the window-lifecycle state machine in detail.

## Data model

```
Project ──┬── Iteration[]   (cascade delete; .sprint | .milestone; isArchived = soft hide)
          └── Ticket[]      (cascade delete; isImported flag for Jira-sourced rows)
                  │
                  └── TimeEntry[]   (cascade delete; hours stored as decimal hours)
```

`Iteration` deletion nullifies `Ticket.iteration` rather than cascading. `Ticket.ticketId` is informational, not a primary key, and not unique — for Jira-imported tickets it holds the Jira issue key (`ABC-123`).

## License

MIT License — feel free to use and modify.
