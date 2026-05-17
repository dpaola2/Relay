# Relay

Relay is an iOS sleep-shift tracker that Dave and Bethany use during the newborn period (Josephine, born 2026-05-14). Single-player v1 on Dave's phone — no App Store, no backend, no auth. Sideload only.

- **WCP namespace:** `RELAY` — check there before starting non-trivial work
- **Founding pitch:** WCP work item `RELAY-1`, artifact `pitch.md`
- **Vault hub:** `~/projects/assistant/05-projects/relay/_index.md`

## Project Shape (the things that won't change)

These are the founding constraints. If a change requires breaking one of them, stop and surface the trade-off — don't quietly relax them.

- **Single-player v1.** Dave's phone logs both his sleep and Bethany's. No second device, no pairing, no shared accounts.
- **No backend.** No server, no API, no auth, no Keychain. Persistence is SwiftData on-device.
- **No HealthKit / Watch.** Manual entry only. The user is half-asleep tapping a big button in the dark.
- **No notifications.** Jo is already making noise.
- **Tiny data model.** One entity (`SleepSession`). Resist adding new entities — most "features" should be views over the same table.
- **Sideload only.** No TestFlight, no App Store, no marketing copy, no privacy labels.
- **Appetite is finite.** One-week paternity-leave build. Out-of-scope work goes back to the WCP `RELAY` backlog, not into the current branch.

## Stack & Platform Settings

Xcode 26.5 SwiftUI + SwiftData scaffold. Settings worth knowing because they will surprise you:

- **iOS deployment target: 26.5.** Use any iOS 26 API without availability checks.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** — every type in the app module is `@MainActor` by default. To run off the main actor, annotate `nonisolated` explicitly.
- **`SWIFT_APPROACHABLE_CONCURRENCY = YES`** and **`SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`** — stricter concurrency diagnostics and explicit member-import visibility.
- Swift 5 language mode, universal (`TARGETED_DEVICE_FAMILY = "1,2"` — iPhone + iPad; ship iPhone only, don't bother gating).
- **File-system synchronized groups** (`PBXFileSystemSynchronizedRootGroup`) — adding a `.swift` file under `Relay/` auto-includes it in the target. No `pbxproj` editing.

## Build & Run

From repo root:

```bash
# Build for the simulator
xcodebuild -project Relay.xcodeproj -scheme Relay \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Clean
xcodebuild -project Relay.xcodeproj -scheme Relay clean

# List simulator destinations
xcrun simctl list devices available
```

Once a test target exists:

```bash
xcodebuild -project Relay.xcodeproj -scheme Relay \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:RelayTests/<TestClass>/<testMethod>
```

`iPhone 17` is the canonical iPhone-class simulator on iOS 26+ (iPhone 16 sims don't exist).

## Persistence (SwiftData)

SwiftData is wired in `Relay/RelayApp.swift` via a single `ModelContainer`. **When you add a new `@Model` type, register it in that `Schema` array.** Forgetting this is the most common reason a new model "exists but never persists." Previews use `.modelContainer(for: ModelName.self, inMemory: true)`.

The starter template's `Item` model and `ContentView`'s items list should be **replaced** as real features land, not built on top of.

## Engineering Methodology

This is a small hobby app, but the rules below still apply — they keep the codebase legible and rewritable when 3 AM Dave needs to fix something.

### 1. TDD by default — Red → Green → Refactor

Write a failing test first. Watch it fail. Write the minimum code to make it pass. Then refactor with the test as your safety net.

- **New features** — the test specifies what "done" means before you start.
- **Bug fixes** — the test reproduces the bug and stays in the suite as a regression guard. A bug fix without a regression test is not done.
- **Refactors** — existing tests stay green; add new ones if you discover untested behavior in the area you're touching.

A test target doesn't exist yet. Adding it is the first task that needs tests — bootstrap the target, write a smoke test, watch the suite go green, then keep going.

### 2. Test behavior, not implementation

Tests describe **what** the system does, not **how**.

- Test the public interface; don't reach into privates.
- Don't test what you don't own (SwiftData, SwiftUI). Test that *your* code sends the right messages to it.
- Incoming messages → assert result. Outgoing commands → assert sent. Outgoing queries → don't assert.
- Mocks belong at boundaries (the SwiftData store, the system clock), not inside your own object graph.
- A test that breaks when you refactor without changing behavior is testing the wrong thing — delete or rewrite it.

### 3. Sandi Metz rules (guardrails, not laws)

- **Types ≤ 100 lines.** Above that, extract.
- **Functions ≤ ~10 lines** (aspirational — use judgment).
- **≤ 4 parameters per function.** More than 4 means you need a struct.
- **View bodies compose subviews.** Don't pile layout and logic into one giant `body` — extract a subview when a view exceeds ~50 lines.

### 4. SOLID, briefly

- **Single Responsibility** — each type has one reason to change. Can't name it without "and"? Extract.
- **Open/Closed** — extend by adding new types, not by editing existing ones.
- **Liskov Substitution** — protocol-conforming types must be drop-in.
- **Interface Segregation** — small, focused protocols beat one fat one.
- **Dependency Inversion** — depend on protocols, inject collaborators so tests can substitute fakes.

### 5. SwiftUI / Swift idioms

- **MVVM with `@Observable`.** Views observe `@Observable` view models. Use the modern Observation framework, not `ObservableObject`.
- **Value types first.** Prefer structs. Use classes only when reference semantics are required (view models, services).
- **Structured concurrency.** `async/await`, `Task`, explicit actor isolation — no GCD, no `DispatchQueue` outside of bridging code.
- **`guard` for early returns, `if let` for optional binding.**
- **Swift API Design Guidelines** — clear at the point of use, prefer clarity over brevity.

### 6. Actor isolation in tests (read before adding the test target)

The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Do **NOT** inherit this setting on the test target — it causes runtime crashes (`malloc: pointer being freed was not allocated`) when test mocks conform to app protocols across actor boundaries. This is established in the sibling iOS apps; learn from it rather than rediscovering.

Pattern that works:

- Service-layer protocols and concrete classes use `nonisolated` to opt out of implicit MainActor.
- View models also use `nonisolated`: `@Observable nonisolated final class FooViewModel`.
- Mocks that conform to app protocols use `@unchecked Sendable`.
- Existential metatype syntax: `(any Protocol).Type`, not `any Protocol.Type`.
- **`ModelContext` is not `Sendable`.** A concrete store conforming to a `Sendable` protocol (e.g. `SleepSessionStore`) must declare `@unchecked Sendable` and treat the context as single-threaded. Revisit when SwiftData ships a `Sendable` `ModelContext`.
- **`EnvironmentKey`/`EnvironmentValues` live in SwiftUI, not Foundation.** Keep SwiftUI environment seams in their own `Foo+Environment.swift` file that imports SwiftUI. Putting them inside a `nonisolated` service file that only imports Foundation/SwiftData fails to compile and forces a SwiftUI dependency on a non-UI type.
- **Avoid shadowing SwiftUI types in your module.** Naming an app-level view `TimelineView` shadows `SwiftUI.TimelineView` inside Relay, breaking any in-module call site that uses the unqualified name. If you must reuse the name, qualify the framework reference: `SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { ... }`. Same idea applies to `Color`, `Image`, `Text`, etc. — pick a distinctive app name (`AppTimelineView`) or qualify the framework call.
- **`Calendar.date(bySettingHour:of:)` rolls forward by default.** The 4-arg convenience wraps `matchingPolicy: .nextTime, direction: .forward`. Asking for hour=7 when the reference date is at hour=14 returns *tomorrow* 7am, not today's 7am — silently bumping the day. To anchor an hour-of-day to the reference date's calendar day, extract `[.year, .month, .day]` components, overlay `hour`/`minute`/`second`, and rebuild via `calendar.date(from: comps)`. See `AddPastSleepViewModel.defaults(now:calendar:)`.
- **`InMemorySleepSessionStore.sessions(in:)` is overlap-based, not start-based.** It returns any session whose `[startedAt, endedAt ?? .distantFuture]` interval touches the range — so an open session started 25h ago will be returned by `sessions(in: lastDay...now)`. If you want strictly "started within the window," post-filter with `.filter { $0.startedAt >= range.lowerBound }`. `SwiftDataSleepSessionStore` should match this contract; verify before relying on either semantic.

### 7. UX for the half-asleep operator

Treat this as a non-negotiable design constraint, not a stretch goal:

- Primary buttons are full-width, high-contrast, and reachable with one thumb.
- Default to dark mode. Avoid white screens at 3 AM.
- The Now screen is the launch screen. No nav drilling to log a session.
- No confirmations on logging actions — taps are reversible via the Edit screen.
- No animations longer than ~150ms on the critical path.

## Project Layout (target, not yet realized)

Mirror the sibling iOS apps in this org — small, focused folders, one type per file.

```
Relay/
├── App/
│   └── RelayApp.swift              # @main entry, ModelContainer setup
├── Models/
│   └── SleepSession.swift          # @Model — the single entity
├── ViewModels/
│   └── NowViewModel.swift          # state for the Now screen
├── Views/
│   ├── Now/                        # three-button log screen
│   ├── Timeline/                   # 72-hour visualization
│   ├── Totals/                     # cumulative sleep numbers
│   └── Edit/                       # session edit list
└── Support/
    └── Extensions/
```

Defer this structure until the second or third file is added — don't pre-create empty folders.

## Git Discipline

- **Commits reference the WCP callsign** they implement: `feat: timeline screen renders 72h band (RELAY-3)`.
- **Run the build before committing.** A broken build wastes the next session's first 10 minutes.
- **Don't push without explicit ask.** This repo is local-only by default.
- **No secrets in source.** (None should exist — there's no backend.)

## What's Out of Scope

If any of the below is requested, push back or surface a trade-off first:

- Feeding / diaper tracking (Bethany uses Huckleberry)
- HealthKit integration
- Apple Watch companion
- Notifications / alarms
- Multi-baby or multi-couple support
- Auth / accounts / user management
- App Store readiness (icon polish, marketing copy, privacy labels)
- Sync via anything other than CloudKit (and that's a v2 concern)
- Sleep coaching or AI-driven recommendations

## Cross-References

- WCP namespace: `RELAY`
- Founding pitch: WCP work item `RELAY-1`, artifact `pitch.md`
- Vault hub: `~/projects/assistant/05-projects/relay/_index.md`
- Sibling iOS apps for code-style reference: `~/projects/show-notes-ios`, `~/projects/wcp-ios`
- Engineering methodology canonical source: `~/projects/assistant/03-living-docs/Engineering-Methodology.md`

## Pipeline Configuration

> Pipeline skills read this section to understand how to run the agent pipeline against this repo.
> Run skills from this repo's root directory (not from the pipeline repo).

### Project Tracker

| Setting | Value |
|---------|-------|
| **Tool** | WCP |
| **Namespace** | `RELAY` |

### Repository Details

| Setting | Value |
|---------|-------|
| **Default branch** | `main` |
| **Test command** | `xcodebuild -project Relay.xcodeproj -scheme Relay -destination 'platform=iOS Simulator,name=iPhone 17' test` |
| **Test directory** | `RelayTests/` (to be created — no test target exists yet) |
| **Branch prefix** | `pipeline/` |
| **PR base branch** | `main` |
| **Build command** | `xcodebuild -project Relay.xcodeproj -scheme Relay -destination 'platform=iOS Simulator,name=iPhone 17' build` |

### Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| iOS | Active | iOS 26.5 deployment target, iPhone-only in practice. Sideload-only — no TestFlight, no App Store. |

### Framework & Stack

| Setting | Value |
|---------|-------|
| **Language** | Swift 5 (language mode) |
| **Framework** | SwiftUI + SwiftData |
| **Test framework** | XCTest (test target not yet created) |
| **Xcode** | 26.5 |
| **iOS deployment target** | 26.5 |
| **Persistence** | SwiftData (`ModelContainer` in `RelayApp.swift`) |
| **Observation** | `@Observable` (modern Observation framework — not `ObservableObject`) |
| **Concurrency** | Structured concurrency (`async/await`, `Task`); `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on app target |
| **Project layout** | File-system synchronized groups (`PBXFileSystemSynchronizedRootGroup`) — adding a `.swift` under `Relay/` auto-includes it |

### Directory Structure

| Purpose | Path |
|---------|------|
| App entry | `Relay/RelayApp.swift` |
| Starter model (to be replaced) | `Relay/Item.swift` |
| Starter view (to be replaced) | `Relay/ContentView.swift` |
| Assets | `Relay/Assets.xcassets/` |
| Xcode project | `Relay.xcodeproj/` |
| Target app folders (to materialize as features land) | `Relay/App/`, `Relay/Models/`, `Relay/ViewModels/`, `Relay/Views/`, `Relay/Support/` |
| Test target (to be created) | `RelayTests/` |

### Implementation Order

1. Model(s) — `@Model` SwiftData entities + register in `Schema` in `RelayApp.swift`
2. Service(s) / repository protocols — `nonisolated` boundaries for testability
3. ViewModel(s) — `@Observable nonisolated final class`
4. View(s) — small, composed subviews under `Relay/Views/<Feature>/`
5. Wire-up in `RelayApp.swift` / parent views
6. Tests follow Red → Green → Refactor at each step (write failing test before code)

### Guardrails

| Guardrail | Rule |
|-----------|------|
| **Production access** | Agents NEVER have production access. Sideload only — no signing keys, no distribution. |
| **Default branch** | Never commit or merge directly to `main`. |
| **Push** | Never push without explicit user request. This repo is local-only by default. |
| **Destructive operations** | No SwiftData migration that drops data without human approval. No mass-delete `Relay/` files. |
| **Project shape** | Do NOT relax the founding constraints in §"Project Shape" (single-player, no backend, no HealthKit, no notifications, one entity, sideload). Surface the trade-off first. |
| **Actor isolation** | Test target MUST NOT inherit `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Service protocols and view models use `nonisolated`. Mocks use `@unchecked Sendable`. |
| **Schema registration** | Every new `@Model` must be added to the `Schema` array in `RelayApp.swift`. |
| **Test-target file inclusion** | `RelayTests/` is a `PBXFileSystemSynchronizedRootGroup` like `Relay/` — adding a `.swift` under it auto-includes it. Per-milestone gating uses `EXCLUDED_SOURCE_FILE_NAMES` (glob form `$(SRCROOT)/RelayTests/<subdir>/*`) in the `RelayTests` target's build settings. M1 excludes `Mocks/`, `Models/`, `Services/`, `Support/`, `ViewModels/`; each subsequent milestone removes the relevant entry. Editing this list is the unblock when a new test file refuses to compile. |

### Post-Flight Checks

| Check | Command | Blocking |
|-------|---------|----------|
| Build | `xcodebuild -project Relay.xcodeproj -scheme Relay -destination 'platform=iOS Simulator,name=iPhone 17' build` | Yes |
| Test (once test target exists) | `xcodebuild -project Relay.xcodeproj -scheme Relay -destination 'platform=iOS Simulator,name=iPhone 17' test` | Yes |
