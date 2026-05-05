# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

macOS-only menu bar time-tracking app (no Dock icon — `NSApp.setActivationPolicy(.accessory)`). SwiftUI + SwiftData. Min deployment target: macOS 14.0. Bundle ID: `cz.bicisteadm.WorklogApp`. Database: SQLite at `~/Library/Application Support/WorklogApp.sqlite`.

## Common Commands

The `Makefile` wraps `xcodebuild` with ad-hoc signing flags — prefer it over raw `xcodebuild`:

```bash
make              # Release build + install to /Applications
make build        # Release build only
make debug        # Debug build only
make run          # Build Release and launch
make test         # Run unit tests
make icon         # Regenerate app icon via scripts/generate_icon.swift
make clean        # Remove DerivedData
```

Raw test command (with required ad-hoc signing flags):
```bash
xcodebuild test -project WorklogApp.xcodeproj -scheme WorklogApp \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Single test: append `-only-testing:WorklogAppTests/WorklogAppTests/<testMethodName>` to the test command.

CI (`.github/workflows/build.yml`) builds arm64, x86_64, and a universal binary on tag pushes (`v*.*.*`) and PRs to `main`.

## Architecture

### Data Model (`WorklogApp/Models/`)
Hierarchy: **Project → Iteration → Ticket → TimeEntry**

- `Project` owns `Ticket[]` and `Iteration[]` via cascade delete
- `Ticket` owns `TimeEntry[]` via cascade delete
- `Iteration` deletion **nullifies** `Ticket.iteration` (does not delete tickets); has `IterationType` enum (`.sprint` | `.milestone`)
- `Iteration.isArchived: Bool` — archived iterations stay in the DB but are filtered out of project-wide / "All" views, and their tickets don't appear in new-ticket pickers. They show up under a collapsed "Archived" section in the sidebar; clicking one drills into its tickets normally. Archive is a soft hide, not a delete — never cascade or remove data based on it.
- `Ticket.ticketId` is **optional/informational** — not unique, not a primary key. SwiftData generates the PK. Conditionally render with `!ticket.ticketId.isEmpty`
- `TimeEntry.hours` stores duration as **decimal hours** (1.5 = 1h 30min). Display via `formatDuration()` → `"Xh Ymin Zs"` everywhere

The `ModelContainer` is constructed in `WorklogAppApp.init()` with an explicit URL pointing at Application Support — not the default location.

### Scenes & Shared State

- `MenuBarExtra` (style `.menu`) shows live timer in the menu bar label; `WindowGroup(id: "main")` is the main window
- A single `TimerState` (`@StateObject` in `WorklogAppApp`) is shared between menu bar and main window. Pass it explicitly to child views — do not create new instances
- `TimerState` publishes a per-second `elapsed: TimeInterval` (driven by an `RunLoop.main` `Timer` in `.common` mode) plus stable state (`isRunning`, `isPaused`, `currentTicket`, `continuingEntry`). Live displays read `Text(formatDuration(timerState.elapsed))`. **Do not** swap this for `Text(timerInterval:)` — using it inside `MenuBarExtra`'s `label:` slot freezes the entire app on `start()` (runaway render/snapshot loop). The perf optimization that prevents lag is on the *consumer* side, not the producer: heavy parents (rows) take plain `let` flags rather than observing `TimerState`.
- Timer save logic lives in one place: `TimerState.stopAndPersist(in: ModelContext)`. It handles both new entries and "continuing" an existing entry (appending hours, merging notes with newline). Don't recreate this in views.
- Per-ticket timer notes (the inline note field) are stored in a private `[PersistentIdentifier: String]` dict — not `@Published`, so typing doesn't repaint anything; the TextField's binding handles its own state.

### Views Layout

- `ContentView.swift` — main window, `NavigationSplitView` (sidebar / ticket list / detail)
- `WorklogApp/Views/` — extracted view files: `SidebarView`, `TicketListView`, `TicketDetailView`, `ReportsView`, `EditTimeEntryView`, plus `*Sheets.swift` files for create/edit modals, and `Helpers.swift`
- `StatusBarMenuView.swift` — content of the `MenuBarExtra` dropdown (just SwiftUI; there is no AppKit `NSStatusItem`)
- `WindowOpener` (in `WorklogAppApp.swift`) — single source of truth for "show the main window". Uses modern `NSApp.activate()` (macOS 14+), inserts `.moveToActiveSpace` on the window's collection behavior so it follows the user across Spaces, deminiaturizes if needed. Call this from anywhere that needs to bring the window forward — don't reinvent it.

### UI Conventions

- Ticket editing happens **inline** in `TicketDetailView` only (`isEditing` toggle). There is no edit-ticket sheet — don't add one back.
- `TicketRowView` takes plain `let isTimerActiveHere: Bool` / `isPaused: Bool` from the parent rather than observing `TimerState`. This is intentional — observing the full `TimerState` from each row is what caused the per-second repaint perf bug. If you need timer info in a row, compute it in the parent and pass it down.
- `.id(ticket.id)` on `TicketDetailView` forces view recreation on ticket switch (resets edit mode and local state)
- For views that take a pre-selected value from parent context, initialize `@State` in `init` via `_propertyName = State(initialValue:)` rather than syncing in `onAppear`/`onChange` (avoids race conditions). See `NewTicketView`, `EditTicketView`
- `.textSelection(.enabled)` on read-only `Text` views for copy support
- `selectedTicket` drives both list highlight and detail panel — when switching context, set it (not nil)

## Conventions

- All code, comments, identifiers, and commit messages in **English**
- No unique constraint on `Ticket.ticketId` — keep it that way
- Unit tests in `WorklogAppTests/WorklogAppTests.swift` cover model relationships and timer behavior; cover happy path + edge cases for changes
