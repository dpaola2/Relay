# Relay

> **Relay treats sleep as recovery and proposes tonight's split based on who's more depleted — so two tired adults don't have to negotiate at 3am.**

A personal iOS sleep-shift tracker for Dave + Bethany during Josephine's newborn period. Built during paternity leave, May 2026. Sideload-only — not on the App Store, never will be.

This is not a product. It's a tool for one couple, designed for one season.

---

## Screens

### Now — log a shift in one tap, half-conscious, in the dark

![Now tab](Screenshots/Now.png)

Three big buttons that work one-handed at 3am: *I'm sleeping*, *Bethany sleeping*, *On duty*. Whichever session is open shows its running duration at the top. Tap once when you go down, tap *On duty* when you wake up. That's it.

### Timeline — yesterday's reality + tonight's plan, on one vertical day

![Timeline tab](Screenshots/Timeline.png)

A Huckleberry-style vertical day view: hour rail down the left, two parallel lanes (Dave terracotta, Bethany soft peach), solid blocks for logged sleep above the now line, proposed shifts below it. Swipe between days. *Sleep is recovery* — the empty state explains why Relay needs data before it can propose anything useful.

### Totals — how depleted is each of you, right now

![Totals tab](Screenshots/Totals.png)

Cumulative sleep over the last 24h / 48h / 72h, per person. A sleep-debt indicator surfaces whoever is more behind on rest. This is the data the Forecast proposal uses to decide who gets tonight's long block.

### Edit — fix what you forgot to tap, add what you forgot to log

![Edit tab](Screenshots/Edit.png)

A scrollable 7-day list of every session. Tap to adjust timestamps (you *will* forget to hit the button, and sessions will be off by 20-30 minutes routinely). Tap the `+` to add a past session you missed entirely — including backfilling the first two days of using the app, when the proposal has no data yet.

### Settings — seed test data, wipe the slate

![Settings tab](Screenshots/Settings.png)

Debug-build affordances for QA: seed sample data, seed a specific Forecast scenario (auto-proposal, manual overrides, empty state), wipe everything. Lets us prove out edge cases without waiting for real 3am moments to reproduce them.

---

## How it thinks — the seven Care Principles

Relay's design is grounded in seven beliefs about the postpartum period. They're not in the app as a manifesto — they live in the algorithms and in a handful of quiet design moments (the "Why this split?" sheet, the empty states, the first-run card). They are the *why* underneath every feature.

1. **Sleep is recovery, not luxury.** Especially in the fourth trimester. Every hour is medicine.
2. **Plan when clear. Trust the plan at 3am.** Decisions in extreme fatigue are systematically worse than decisions when rested.
3. **Data over scorekeeping.** Both parents see the same numbers. Nobody is tracking the other.
4. **The auto-proposal is the value statement.** Splits are based on present sleep debt — never on history of who has done more.
5. **The plan is a starting place. Deviation is expected.** Newborn sleep is chaos. The plan is a tool, not a verdict.
6. **One day at a time.** No streaks, no week views, no long-horizon goals. The fourth trimester is a season.
7. **The tool proposes. You decide.** Relay surfaces the data and gets out of the way; it doesn't coach.

Full strategy docs:
- [Care Principles](../assistant/05-projects/relay/strategy/care-principles.md) — the *why*
- [JTBD framework](../assistant/05-projects/relay/strategy/jtbd.md) — the five jobs Relay serves

---

## What it deliberately is not

- Not a baby tracker (feeds, diapers, weight). Huckleberry already does that.
- Not a sleep-quality scorer. No stages, no scores, no coaching.
- Not a notifier or alarm. The phone is already making noise.
- Not on the App Store. Sideload-only.
- Not multi-couple, multi-baby, or generalized. One couple, one newborn, one season.
- No HealthKit, no Apple Watch, no backend, no auth, no accounts.

---

## Stack

- SwiftUI + SwiftData (local persistence)
- iPhone-only, dark theme, single-player on Dave's phone for v1
- One entity: `SleepSession { who, startedAt, endedAt, note }` (+ `ProposedShift` for Forecast)
- No backend, no analytics, no telemetry
- ~86 tests + Forecast/Backfill/Palette/Timeline additions, TDD throughout

## Status (as of 2026-05-17)

Shipped to Dave's phone:

| Version | Pitch | What landed |
|---|---|---|
| v1.0 | RELAY-1 | Now / Timeline (horizontal) / Totals / Edit, sleep-debt math |
| v1.1 | RELAY-2 + RELAY-3 | Backfill sheet + warm palette (cream / terracotta / ink) |
| v1.2 | RELAY-4 | Vertical Timeline (Huckleberry-style Day view, two lanes) |
| v1.3 | RELAY-5 | Forecast — auto-proposed 18h shift plan, "Why this split?" affordance, Care Principles surfaced in empty state and first-run card |

Backlog: RELAY-6 (seconds tick on Now banner — live-tracking affordance, chore).

## Build & sideload

Open `Relay.xcodeproj` in Xcode. Build target: iPhone, signed with personal developer team. Sideload via Xcode → physical device. No TestFlight, no App Store metadata.

In-repo engineering conventions: `CLAUDE.md`.

---

## Cross-references

- WCP namespace: `RELAY` (work items + pitches + artifacts)
- Strategy: [Care Principles](../assistant/05-projects/relay/strategy/care-principles.md) + [JTBD](../assistant/05-projects/relay/strategy/jtbd.md)
- Project hub: [Relay in Dave's OS](../assistant/05-projects/relay/_index.md)
- Repo: this directory (`~/projects/Relay`)
