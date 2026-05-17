//
//  WhyThisSplitSheetTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M8: Philosophy Surface Moments)
//
//  Covers gameplan acceptance criteria:
//    - PHL-002: WhyThisSplitSheet copy contains fixed-text Care Principle
//      paragraphs (sleep is recovery; this isn't about turns).
//    - PHL-002: total body ≤120 words.
//    - PHL-004: ForecastEmptyState copy has the documented title, body,
//      action label, and secondary line.
//    - PHL-005: ForecastFirstRunCard copy has the documented title, body,
//      and action label.
//    - PHL-007: WhyThisSplitSheet, ForecastEmptyState, and
//      ForecastFirstRunCard copy MUST NOT contain "wellness", "balance",
//      "self-care", or "mindful".
//
//  These tests assert on plain-text content exposed by the view types (e.g.,
//  as a static `bodyCopy: String` property or similar). View-body snapshot
//  testing is intentionally avoided per the gameplan's "behavior-test, not
//  snapshot-test" guidance.
//
//  Expected to FAIL until Stage 5 lands:
//    (a) `Relay/Views/Timeline/WhyThisSplitSheet.swift`
//    (b) `Relay/Views/Timeline/ForecastEmptyState.swift`
//    (c) `Relay/Views/Timeline/ForecastFirstRunCard.swift`
//

import XCTest
@testable import Relay

final class WhyThisSplitSheetTests: XCTestCase {

    // MARK: - PHL-002: fixed-text Care Principle paragraphs

    func test_bodyCopy_containsSleepIsRecoveryParagraph() {
        let copy = WhyThisSplitSheet.bodyCopy
        XCTAssertTrue(
            copy.contains("Sleep is recovery"),
            "PHL-002: must contain the 'Sleep is recovery' Care Principle paragraph"
        )
        XCTAssertTrue(
            copy.contains("more depleted parent gets the longer block"),
            "PHL-002: must contain the deficit-grounded explanation"
        )
    }

    func test_bodyCopy_containsNoTurnsParagraph() {
        let copy = WhyThisSplitSheet.bodyCopy
        XCTAssertTrue(
            copy.contains("isn't about whose turn it is"),
            "PHL-002: must contain the 'not about turns' Care Principle paragraph"
        )
        XCTAssertTrue(
            copy.contains("Relay doesn't track turns"),
            "PHL-002: must explicitly state Relay doesn't track turns"
        )
    }

    // MARK: - PHL-002: total body ≤120 words

    func test_bodyCopy_isAtMost120Words() {
        let copy = WhyThisSplitSheet.bodyCopy
        let words = copy
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
        XCTAssertLessThanOrEqual(
            words,
            120,
            "PHL-002: total body ≤120 words (got \(words))"
        )
    }

    // MARK: - PHL-007: banned words

    func test_bodyCopy_doesNotContainBannedWords() {
        let copy = WhyThisSplitSheet.bodyCopy.lowercased()
        for banned in ["wellness", "balance", "self-care", "mindful"] {
            XCTAssertFalse(
                copy.contains(banned),
                "PHL-007: WhyThisSplitSheet copy must not contain '\(banned)'"
            )
        }
    }
}

// MARK: - ForecastEmptyState

final class ForecastEmptyStateTests: XCTestCase {

    func test_title_isSleepIsRecovery() {
        XCTAssertEqual(
            ForecastEmptyState.titleCopy,
            "Sleep is recovery.",
            "PHL-004: empty-state title is the fixed Care Principle line"
        )
    }

    func test_bodyCopy_containsDocumentedSentence() {
        let body = ForecastEmptyState.bodyCopy
        XCTAssertTrue(
            body.contains("Relay proposes tonight's split when it knows how depleted each of you is"),
            "PHL-004: empty-state body must contain the documented sentence"
        )
    }

    func test_primaryActionLabel_addsTheLastTwoDays() {
        XCTAssertEqual(
            ForecastEmptyState.primaryActionLabel,
            "Add the last two days",
            "PHL-004: empty-state primary action label"
        )
    }

    func test_secondaryLineCopy_containsFallbackPrompt() {
        XCTAssertTrue(
            ForecastEmptyState.secondaryLineCopy.contains(
                "just start logging tonight"
            ),
            "PHL-004: empty-state secondary line"
        )
    }

    // PHL-007 — empty state shares the no-banned-words rule.
    func test_allCopy_doesNotContainBannedWords() {
        let composite = (
            ForecastEmptyState.titleCopy + " " +
            ForecastEmptyState.bodyCopy + " " +
            ForecastEmptyState.secondaryLineCopy
        ).lowercased()

        for banned in ["wellness", "balance", "self-care", "mindful"] {
            XCTAssertFalse(
                composite.contains(banned),
                "PHL-007: empty-state copy must not contain '\(banned)'"
            )
        }
    }
}

// MARK: - ForecastFirstRunCard

final class ForecastFirstRunCardTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "relay.tests.firstruncard"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // PHL-005 — fixed-text copy

    func test_titleCopy_isThisIsAStartingPlace() {
        XCTAssertEqual(
            ForecastFirstRunCard.titleCopy,
            "This is a starting place."
        )
    }

    func test_bodyCopy_containsDocumentedPhrases() {
        let body = ForecastFirstRunCard.bodyCopy
        XCTAssertTrue(body.contains("Tap any block to adjust"))
        XCTAssertTrue(body.contains("The plan is yours"))
        XCTAssertTrue(body.contains("Deviation is expected"))
    }

    func test_actionLabel_isGotIt() {
        XCTAssertEqual(ForecastFirstRunCard.actionLabel, "Got it")
    }

    // PHL-006 — permanence behavior is asserted at the flag layer
    // (`ForecastFirstRunFlagTests.test_dismissed_isPermanent_noPathToReset`);
    // here we assert the view's `shouldRender(flag:)` decision uses the flag.

    func test_shouldRender_returnsTrue_whenFlagNotDismissed() {
        let flag = ForecastFirstRunFlag(defaults: defaults)
        XCTAssertTrue(ForecastFirstRunCard.shouldRender(flag: flag))
    }

    func test_shouldRender_returnsFalse_whenFlagDismissed() {
        let flag = ForecastFirstRunFlag(defaults: defaults)
        flag.dismissed = true
        XCTAssertFalse(
            ForecastFirstRunCard.shouldRender(flag: flag),
            "PHL-006: once dismissed, card must not render"
        )
    }

    // PHL-007 — no banned words
    func test_allCopy_doesNotContainBannedWords() {
        let composite = (
            ForecastFirstRunCard.titleCopy + " " +
            ForecastFirstRunCard.bodyCopy
        ).lowercased()

        for banned in ["wellness", "balance", "self-care", "mindful"] {
            XCTAssertFalse(
                composite.contains(banned),
                "PHL-007: first-run card copy must not contain '\(banned)'"
            )
        }
    }
}
