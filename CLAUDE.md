# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

macOS-only time-tracking app, hybrid menu-bar/Dock — launches as a regular `.regular` Dock app with the main window, drops to `.accessory` (menu-bar-only, no Dock icon) after the user closes the window. SwiftUI + SwiftData. Min deployment target: macOS 14.0. Bundle ID: `cz.bicisteadm.WorklogApp`. Database: SQLite at `~/Library/Application Support/WorklogApp.sqlite`. See *Activation policy & window lifecycle* below for the lifecycle state machine.

## Common Commands

The `Makefile` wraps `xcodebuild` with ad-hoc signing flags — prefer it over raw `xcodebuild`:

```bash
make              # Release build + install to /Applications
make build        # Release build only
make debug        # Debug build only (produces WorklogApp-Dev.app)
make dev-run      # Debug build + launch dev instance (side-by-side with prod)
make dev-install  # Copy WorklogApp-Dev.app to /Applications
make run          # Build Release and launch
make test         # Run unit tests
make icon         # Regenerate app icon via scripts/generate_icon.swift
make clean        # Remove DerivedData (both projects)

make bridge       # Build + install SkodaAtlassianBridge.app to /Applications
make bridge-build # Build the bridge only
make bridge-run   # Build and launch the bridge
```

### Dev vs. production instance

For **all development work — building, running, testing, screenshotting** — use the **Dev instance** only. **Never touch the production app** (`make`, `make build`, `make install`, `make run`) unless the user explicitly asks for a production deploy.

The Dev instance is fully isolated from production and the user keeps both running side by side:

| | Production | Dev |
|---|---|---|
| Bundle ID | `cz.bicisteadm.WorklogApp` | `cz.bicisteadm.WorklogApp.dev` |
| App bundle | `WorklogApp.app` | `WorklogApp-Dev.app` |
| Display name | `WorklogApp` | `WorklogApp Dev` |
| Database | `~/Library/Application Support/WorklogApp.sqlite` | `~/Library/Application Support/WorklogApp-Dev.sqlite` |
| Menu bar icon | `clock` / `timer` / `pause.circle` | `hammer` / `hammer.fill` / `hammer.circle` + orange **DEV** text |
| UserDefaults / window autosave | separate (per bundle ID) | separate (per bundle ID) |

Dev/prod split is driven by `#if DEBUG` (DB filename, menu bar icon, "DEV" label) plus per-configuration `PRODUCT_BUNDLE_IDENTIFIER` / `PRODUCT_NAME` / `INFOPLIST_KEY_CFBundleDisplayName` in `WorklogApp.xcodeproj`. When adding new persistent state (files, defaults keys, sockets, ports), make sure it inherits the same isolation — otherwise dev work will corrupt the user's real worklog data.

`SkodaAtlassianBridge/` is a **separate Xcode project** in this repo (sibling app, not a framework). It is currently a **POC** — it has scaffolding for an out-of-process Atlassian session host (`AtlassianSession.swift`, `IPC/UnixSocketServer.swift`, `IPC/BridgeRouter.swift`, `IPC/BridgeAPI.swift`, `IPC/TokenStore.swift`), but **`WorklogApp` does not consume it yet**. WorklogApp still does Jira in-process via its own `JiraBridge.swift` (embedded `WKWebView`). The two apps share nothing at build or runtime — don't move bridge code into the WorklogApp target, and don't assume the IPC channel is wired up.

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
- `Ticket.ticketId` is **optional/informational** — not unique, not a primary key. SwiftData generates the PK. Conditionally render with `!ticket.ticketId.isEmpty`. For Jira-imported tickets this field holds the Jira issue key (e.g. `ABC-123`)
- `Ticket.isImported` marks rows created by the Jira importer. These are **read-only** in the UI — fields refresh on next sync, never by inline edit. Don't add edit affordances for imported tickets, and never overwrite a manually-created ticket that happens to share a key (importer skips and logs an error)
- `TimeEntry.hours` stores duration as **decimal hours** (1.5 = 1h 30min). Display via `formatDuration()` → `"Xh Ymin Zs"` everywhere
- Jira-related model fields are additive metadata: `Project.jiraJQL` / `jiraSprintFieldId` / `lastJiraSync`, `Iteration.jiraSprintId` / `jiraSprintState`, `Ticket.jiraIssueId` / `jiraLastSync`. Empty `jiraJQL` ⇒ project is not Jira-synced (`Project.isJiraSynced`). Sprints with `jiraSprintState == "CLOSED"` are auto-archived on import

The `ModelContainer` is constructed in `WorklogAppApp.init()` with an explicit URL pointing at Application Support — not the default location.

### Scenes & Shared State

- Scenes in `WorklogAppApp.body`: `MenuBarExtra` (style `.menu`, live timer in the label) + `WindowGroup(id: WindowIDs.main)` (main window) + standalone `Window(id: WindowIDs.reports)` (Reports opens as its own NSWindow, not a sheet) + `Window(id: WindowIDs.jiraLogin)` + the `Settings` scene. `WindowIDs` registry lives in `JiraLoginWindow.swift`
- A single `TimerState` (`@StateObject` in `WorklogAppApp`) is shared between menu bar and main window. Pass it explicitly to child views — do not create new instances
- `TimerState` publishes a per-second `elapsed: TimeInterval` (driven by an `RunLoop.main` `Timer` in `.common` mode) plus stable state (`isRunning`, `isPaused`, `currentTicket`, `continuingEntry`). Live displays read `Text(formatDuration(timerState.elapsed))`. **Do not** swap this for `Text(timerInterval:)` — using it inside `MenuBarExtra`'s `label:` slot freezes the entire app on `start()` (runaway render/snapshot loop). The perf optimization that prevents lag is on the *consumer* side, not the producer: heavy parents (rows) take plain `let` flags rather than observing `TimerState`.
- Timer save logic lives in one place: `TimerState.stopAndPersist(in: ModelContext)`. It handles both new entries and "continuing" an existing entry (appending hours, merging notes with newline). Don't recreate this in views.
- Per-ticket timer notes (the inline note field) are stored in a private `[PersistentIdentifier: String]` dict — not `@Published`, so typing doesn't repaint anything; the TextField's binding handles its own state.

### Views Layout

- `ContentView.swift` — main window, `NavigationSplitView` (sidebar / ticket list / detail)
- `WorklogApp/Views/` — extracted view files: `SidebarView`, `TicketListView`, `TicketDetailView`, `ReportsView`, `EditTimeEntryView`, plus `*Sheets.swift` files for create/edit modals, and `Helpers.swift`
- `StatusBarMenuView.swift` — content of the `MenuBarExtra` dropdown (just SwiftUI; there is no AppKit `NSStatusItem`). The "Open WorklogApp" button calls **both** `openWindow(id: WindowIDs.main)` (captured from `@Environment(\.openWindow)`) **and** `WindowOpener.bringForward()` — in that order. openWindow creates/reuses the SwiftUI WindowGroup window; bringForward flips activation policy and orders it above foreign apps.
- `WindowOpener` (in `WorklogAppApp.swift`) — helpers for the post-openWindow activation step only. Does `setActivationPolicy(.regular)` + `NSApp.activate(ignoringOtherApps: true)` + `makeKeyAndOrderFront` + `orderFrontRegardless`. It does NOT create windows — that's openWindow's job.

### Activation policy & window lifecycle — DO NOT OVER-ENGINEER

The app is a hybrid menu-bar/regular app. The intentional minimal architecture:

| Trigger | Owner | Effect |
|---|---|---|
| Cold launch | `AppDelegate.applicationDidFinishLaunching` | `setActivationPolicy(.regular)` → SwiftUI auto-creates the WindowGroup window like a normal Dock app |
| Last window closed (red X / Cmd-W) | `AppDelegate.applicationShouldTerminateAfterLastWindowClosed` | returns `false` + `setActivationPolicy(.accessory)` — Dock icon vanishes, menu bar item stays |
| Yellow minimize | (no hook fires — by design) | Window stays alive minimized, policy stays `.regular`, Dock icon stays |
| Menu bar "Open" button | `MenuBarContentView` | `openWindow(id:)` + `WindowOpener.bringForward()` |
| Dock icon click (briefly visible) | `AppDelegate.applicationShouldHandleReopen` | `WindowOpener.bringForward()` |

**Things that were tried and made it worse — do not reintroduce:**
- Custom `NSWindowDelegate` to intercept `windowShouldClose` and `orderOut` instead of closing — breaks SwiftUI's WindowGroup lifecycle in subtle ways even with delegate-chain forwarding via `responds(to:)` / `forwardingTarget(for:)`.
- `OpenWindowBridge` (an invisible SwiftUI view with `@Environment(\.openWindow)` listening to a `NotificationCenter` channel posted by AppDelegate) — neither MenuBarExtra's `content` slot (lazy-mounted while menu is open) nor its `label` slot (rendered as a bitmap snapshot for the menu bar icon) keeps the view reliably mounted enough to receive notifications.
- `WindowConfigurator` as an NSViewRepresentable in `ContentView.background` that mutated activation policy on appear and installed a `willCloseNotification` observer — runs after the window is already on screen so it's useless at cold launch, and `willCloseNotification` fires during termination too, causing extra policy churn.
- Trying to "promote then activate then demote" the policy on demand around an openWindow call to coerce cross-app focus — macOS 14's `NSApp.activate()` is too polite for accessory apps and the dance just adds flicker.

The simple combination — `openWindow(id:)` from the captured Environment closure + `WindowOpener.bringForward()` doing the AppKit dance afterwards — is the only thing that reliably works across cold launch, close-then-reopen, and cross-app activation. **Don't add NSWindowDelegate hooks, notification bridges, or AppDelegate-side openWindow shims. They've all been tried and they all regress something.**

### UI Conventions

- Ticket editing happens **inline** in `TicketDetailView` only (`isEditing` toggle). There is no edit-ticket sheet — don't add one back.
- `TicketRowView` takes plain `let isTimerActiveHere: Bool` / `isPaused: Bool` from the parent rather than observing `TimerState`. This is intentional — observing the full `TimerState` from each row is what caused the per-second repaint perf bug. If you need timer info in a row, compute it in the parent and pass it down.
- `.id(ticket.id)` on `TicketDetailView` forces view recreation on ticket switch (resets edit mode and local state)
- For views that take a pre-selected value from parent context, initialize `@State` in `init` via `_propertyName = State(initialValue:)` rather than syncing in `onAppear`/`onChange` (avoids race conditions). See `NewTicketView`, `EditTicketView`
- `.textSelection(.enabled)` on read-only `Text` views for copy support
- `selectedTicket` drives both list highlight and detail panel — when switching context, set it (not nil)

### Jira Integration (`JiraBridge.swift`, `JiraImporter.swift`, `JiraLoginWindow.swift`, `AppSettings.swift`)

The company-internal Jira has the public REST API disabled, so the bridge **does not use `URLSession`**. Instead:

- A single retained `WKWebView` (`JiraBridge.webView`) carries the user's authenticated session cookies (F5 / SSO / Jira) in a persistent `WKWebsiteDataStore.default()`. REST calls are issued from inside the page context via `callAsyncJavaScript(...)` running `fetch()` — so F5 sees a normal authenticated browser request. Don't replace this with `URLSession`; cookies, CSRF, and F5 headers all depend on running inside the page
- Use `callAsyncJavaScript`, **not** `evaluateJavaScript` for the async overload — the latter trips on "unsupported type" when the resolved Promise contains null/undefined inside an object
- `JiraBridge.validate()` is **strictly on-demand** — there is no background watchdog. It runs only on user "Test" click, while the login window polls during sign-in, or right before a real API operation. Don't add periodic pings; the constraint is to keep the request profile minimal so it looks like real user activity
- `MTLSNavigationDelegate` handles client-cert (mTLS) auth via `SecItemCopyMatching` on `kSecClassIdentity` and shows `SFChooseIdentityPanel` for multi-identity cases. It also accumulates a 200-line diagnostic log surfaced in the login window — append to it (`navDelegate.log(...)`) when adding new bridge operations so the user can debug silent failures
- `JiraImporter.sync(project:in:)` does the full pipeline: discovers the sprint custom field (`com.pyxis.greenhopper.jira:gh-sprint`) and caches its ID on the `Project`, paginates `/rest/api/2/search?jql=...` 100 at a time, then upserts iterations (by `jiraSprintId`) and tickets (by `ticketId == issue.key`). Sprint refs come through `JiraIssue.raw` because the customfield key varies per instance
- **Reconcile pass** after the upsert loop: any `isImported` ticket on the project that the current JQL no longer returns is either **deleted** (if `entries.isEmpty`) or **kept as orphan** (if it has logged time). Matching uses both `ticketId` (key) and `jiraIssueId` for robustness against issues moved between projects. Counts surface in `Summary.ticketsDeleted` / `ticketsOrphaned` in the sync result dialog. Changing a project's JQL therefore actively prunes — `EditProjectView` shows an inline warning when the JQL is dirty and the project has synced before
- Sprint values from Jira come in **two formats** — modern JSON objects and the legacy `com....Sprint@hash[id=...,name=...,...]` string form. `SprintParser.parse` handles both. Don't drop the legacy path
- Ticket summary is stripped to plain text via `JiraText.plainText(from:)`; description keeps raw HTML and is rendered with `JiraText.attributed(from:)` (which strips HTML-parser-injected fonts/colors so it adapts to dark mode and the SwiftUI environment font)
- `AppSettings.jiraBaseURL` lives in `UserDefaults`; cookies live in the shared `WKWebsiteDataStore`. There is no Keychain entry for Jira credentials — auth is entirely cookie-based

## Conventions

- All code, comments, identifiers, and commit messages in **English**
- No unique constraint on `Ticket.ticketId` — keep it that way
- Unit tests in `WorklogAppTests/WorklogAppTests.swift` cover model relationships and timer behavior; cover happy path + edge cases for changes
