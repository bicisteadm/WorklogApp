# WorklogApp — AI Agent Instructions

## Project Overview
macOS-only menu bar time-tracking app. No Dock icon — runs via `MenuBarExtra`. Built with **SwiftUI + SwiftData** (SQLite at `~/Library/Application Support/WorklogApp.sqlite`). Minimum deployment target: macOS 14.0.

## Architecture

### Data Model (`WorklogApp/Models/`)
Hierarchy: **Project → Iteration → Ticket → TimeEntry**
- `Project` owns `Ticket[]` and `Iteration[]` (cascade delete)
- `Ticket` owns `TimeEntry[]` (cascade delete). `ticketId` is **optional/informational** (not unique, not a primary key — SwiftData auto-generates the PK)
- `Iteration` nullifies tickets on delete; has `IterationType` enum (`.sprint` | `.milestone`)
- `TimeEntry.hours` stores duration as **decimal hours** (1.5 = 1h 30min). Display uses `formatDuration()` → `"Xh Ymin Zs"` format everywhere

### Key Components
- **`WorklogAppApp.swift`** — App entry point. `MenuBarExtra` (menu style) + `WindowGroup(id: "main")`. Shared `TimerState` via `@StateObject`
- **`ContentView.swift`** — Main window. `NavigationSplitView` with 3 columns: sidebar (projects/iterations) → ticket list → ticket detail. Contains all view structs (`NewTicketView`, `EditTicketView`, `TicketDetailView`, `ReportsView`, `BulkTicketView`, etc.) in a single file
- **`TimerState.swift`** — `ObservableObject` shared across menu bar and main window. Timer runs on `RunLoop.common` mode so it ticks while menus are open
- **`StatusBarController.swift`** — AppKit `NSStatusItem` wrapper with Combine observations
- **`StatusBarMenuView.swift`** — SwiftUI menu bar dropdown content

### UI Patterns
- Inline editing in `TicketDetailView` (toggle `isEditing` state) — **not** sheet-based
- `.id(ticket.id)` on `TicketDetailView` forces view recreation on ticket switch (resets edit mode)
- `@State` values initialized in `init` via `_propertyName = State(initialValue:)` to avoid `onAppear`/`onChange` race conditions (see `NewTicketView`, `EditTicketView`)
- `.textSelection(.enabled)` on all read-only `Text` views for copy support
- `selectedTicket` drives both list highlight and detail panel — always set it (not nil) when switching context

## Build & Test Commands
```bash
# Debug build
xcodebuild build -project WorklogApp.xcodeproj -scheme WorklogApp \
  -destination 'platform=macOS' -configuration Debug \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Run tests
xcodebuild test -project WorklogApp.xcodeproj -scheme WorklogApp \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Release universal binary (CI does this — see .github/workflows/build.yml)
xcodebuild build ... ARCHS="arm64 x86_64" -configuration Release
```

## Development Rules
- **Language**: All code, comments, variable names, and commit messages in **English**
- **Testing**: Unit tests in `WorklogAppTests/` for models and relationships. Cover happy path + edge cases for every change
- **No unique constraints** on `Ticket.ticketId` — it is purely informational
- **Conditionally display** `ticketId` — check `!ticket.ticketId.isEmpty` before rendering
- When adding new views with pre-selected values from parent context, initialize `@State` in `init`, not `onAppear`
