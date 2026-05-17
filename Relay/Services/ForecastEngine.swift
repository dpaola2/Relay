//
//  ForecastEngine.swift
//  Relay
//
//  Pure, deterministic shift-proposal engine. Plain values in, half-hour cells
//  out. NO SwiftData, NO SwiftUI. The whole expression of Care Principle 4
//  (Architecture §6.1) lives here: proposals are grounded in present 24h sleep
//  deficit per person — never history, never turn-taking, never quotas. The
//  algorithm IS the value statement.
//
//  Algorithm (see PRD §"Auto-proposal logic" + Architecture §6.1):
//    1. Build the planning window via components-overlay (DST-safe; never
//       `Calendar.date(bySettingHour:of:)` — see CLAUDE.md established footgun).
//       Default: 22:00 planDay (LOCAL) → 06:00 planDay+1 (LOCAL).
//    2. Compute total cell count: window duration / 30 minutes.
//    3. If both deficits are zero (or the deficits dict is empty), return [].
//       NO 50/50 fallback (ENG-008 / OQ-5).
//    4. Assign cells proportionally to relative deficit; larger-deficit person
//       gets their block first, contiguously. Tie-break: alphabetical by raw
//       value (deterministic and stable).
//    5. Cap any single block at 10 cells (5h, ENG-005). Overflow is dropped —
//       NOT redistributed to the other person (ENG-005).
//    6. Skip cells whose startedAt aligns with an existing ProposedShift where
//       `manuallyOverridden == true` (ENG-011) — caller preserves those rows.
//

import Foundation

nonisolated struct ForecastEngine {

    // MARK: - Public types

    struct Inputs {
        var planDay: Date                    // start-of-day for the night being planned
        var now: Date                        // reference timestamp (clock.now)
        var calendar: Calendar               // for DST-safe arithmetic
        var deficits: [Person: TimeInterval] // 24h deficit per person (seconds, >= 0)
        var targetHoursPer24h: Double        // typically 8.0
        var planningWindow: PlanningWindow   // default: 22:00 planDay → 06:00 planDay+1
        var existingShifts: [ProposedShift]  // for the same planDay
    }

    struct PlanningWindow {
        var startHour: Int   // 22
        var endHour: Int     // 6 (if endHour <= startHour, end is next day)
    }

    struct ProposedHalfHour: Equatable {
        var startedAt: Date
        var endedAt: Date    // startedAt + 30 min
        var who: Person
    }

    // MARK: - Constants

    /// 30 minutes in seconds. Every cell is exactly this long (ADR-001).
    private static let cellSeconds: TimeInterval = 1800

    /// Single block cap: 5 hours = 10 cells (ENG-005).
    private static let maxCellsPerBlock = 10

    // MARK: - propose

    /// Pure, deterministic.
    /// Returns the proposed half-hour cells for the planning window.
    /// Cells whose start aligns with an existing `ProposedShift.manuallyOverridden == true`
    /// are NOT in the returned array — the caller preserves those rows as-is.
    /// Returns `[]` if both deficits are zero (empty proposal — surfaces empty state).
    func propose(_ inputs: Inputs) -> [ProposedHalfHour] {
        // ENG-008 / EDG-001: both at target → empty proposal. NO 50/50 fallback.
        let daveDeficit = max(0, inputs.deficits[.dave] ?? 0)
        let bethanyDeficit = max(0, inputs.deficits[.bethany] ?? 0)
        if daveDeficit == 0, bethanyDeficit == 0 {
            return []
        }

        // ENG-007 + EDG-008: build window via components-overlay (DST-safe).
        guard let windowStart = anchor(
            hour: inputs.planningWindow.startHour,
            on: inputs.planDay,
            calendar: inputs.calendar
        ) else {
            return []
        }
        guard let windowEnd = endAnchor(
            from: windowStart,
            startHour: inputs.planningWindow.startHour,
            endHour: inputs.planningWindow.endHour,
            calendar: inputs.calendar
        ) else {
            return []
        }

        let totalCells = Int(windowEnd.timeIntervalSince(windowStart) / Self.cellSeconds)
        guard totalCells > 0 else { return [] }

        // ENG-011: collect startedAt values of overridden cells to skip.
        let overriddenStarts: Set<Date> = Set(
            inputs.existingShifts
                .filter(\.manuallyOverridden)
                .map(\.startedAt)
        )

        // Proportional split + larger-deficit-first ordering.
        let (first, second, firstCount, secondCount) = split(
            totalCells: totalCells,
            daveDeficit: daveDeficit,
            bethanyDeficit: bethanyDeficit
        )

        // Emit cells across the contiguous timeline, skipping overridden slots.
        var cells: [ProposedHalfHour] = []
        cells.reserveCapacity(totalCells)
        for index in 0..<totalCells {
            let started = windowStart.addingTimeInterval(Self.cellSeconds * Double(index))
            if overriddenStarts.contains(started) { continue }
            let who: Person? = assignment(
                forIndex: index,
                first: first,
                firstCount: firstCount,
                second: second,
                secondCount: secondCount
            )
            guard let who else { continue }
            cells.append(ProposedHalfHour(
                startedAt: started,
                endedAt: started.addingTimeInterval(Self.cellSeconds),
                who: who
            ))
        }
        return cells
    }

    // MARK: - Helpers

    /// Anchors `hour` onto `date`'s calendar day via the components-overlay
    /// pattern. Pulls [.year, .month, .day] from the reference date and
    /// overlays hour/minute/second to rebuild. Avoids
    /// `Calendar.date(bySettingHour:of:)` which silently rolls forward
    /// (CLAUDE.md established footgun).
    private func anchor(
        hour: Int,
        on date: Date,
        calendar: Calendar
    ) -> Date? {
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        return calendar.date(from: comps)
    }

    /// Computes the planning-window end anchor. When `endHour <= startHour`,
    /// the window wraps past midnight — anchor end on planDay+1. Uses
    /// components-overlay (NOT `bySettingHour`) to remain DST-safe.
    private func endAnchor(
        from windowStart: Date,
        startHour: Int,
        endHour: Int,
        calendar: Calendar
    ) -> Date? {
        let baseDay: Date
        if endHour <= startHour {
            guard let next = calendar.date(
                byAdding: .day,
                value: 1,
                to: windowStart
            ) else { return nil }
            baseDay = next
        } else {
            baseDay = windowStart
        }
        return anchor(hour: endHour, on: baseDay, calendar: calendar)
    }

    /// Splits `totalCells` between the two people in proportion to their
    /// deficits, capping each at `maxCellsPerBlock`. Returns the ordering
    /// (larger-deficit-first) and the cell counts for each block.
    /// Overflow above the cap is dropped — NOT redistributed (ENG-005).
    private func split(
        totalCells: Int,
        daveDeficit: TimeInterval,
        bethanyDeficit: TimeInterval
    ) -> (first: Person, second: Person, firstCount: Int, secondCount: Int) {
        // Determine ordering by deficit; tie-break deterministically on raw
        // value (alphabetical: "bethany" < "dave").
        let bethanyIsLarger: Bool
        if bethanyDeficit != daveDeficit {
            bethanyIsLarger = bethanyDeficit > daveDeficit
        } else {
            bethanyIsLarger = Person.bethany.rawValue < Person.dave.rawValue
        }

        let first: Person = bethanyIsLarger ? .bethany : .dave
        let second: Person = bethanyIsLarger ? .dave : .bethany
        let firstDeficit = bethanyIsLarger ? bethanyDeficit : daveDeficit
        let secondDeficit = bethanyIsLarger ? daveDeficit : bethanyDeficit

        let sum = firstDeficit + secondDeficit
        // sum can be zero only when both deficits are zero, which is handled
        // earlier (ENG-008). Defensive guard nonetheless.
        guard sum > 0 else { return (first, second, 0, 0) }

        // Proportional split, rounded toward larger-deficit person.
        let firstRaw = (Double(totalCells) * firstDeficit / sum).rounded()
        var firstCount = Int(firstRaw)
        firstCount = max(0, min(totalCells, firstCount))
        var secondCount = totalCells - firstCount

        // ENG-005: cap each block at 5h = 10 cells; overflow dropped.
        firstCount = min(firstCount, Self.maxCellsPerBlock)
        secondCount = min(secondCount, Self.maxCellsPerBlock)

        return (first, second, firstCount, secondCount)
    }

    /// Returns the assigned `Person` for `index` within the contiguous
    /// window, or nil if the index is past the assigned blocks (overflow
    /// from a 5h cap is dropped, not reassigned — ENG-005).
    private func assignment(
        forIndex index: Int,
        first: Person,
        firstCount: Int,
        second: Person,
        secondCount: Int
    ) -> Person? {
        if index < firstCount {
            return first
        }
        if index < firstCount + secondCount {
            return second
        }
        return nil
    }
}
