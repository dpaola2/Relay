//
//  DayTimelineSwipeTests.swift
//  RelayTests
//
//  RELAY-8 — pure-function tests for the Day-view swipe gesture. The gesture
//  itself is a `DragGesture` inside `DayTimelineView`, but the decision logic
//  ("given a translation, what direction should we step, if any?") is extracted
//  into `DayTimelineSwipe.direction(translation:)` so it can be unit-tested
//  without SwiftUI gesture plumbing.
//

import XCTest
import CoreGraphics
@testable import Relay

final class DayTimelineSwipeTests: XCTestCase {

    // MARK: - Below threshold → no step

    func test_smallTranslation_returnsNoStep() {
        XCTAssertNil(DayTimelineSwipe.direction(translation: CGSize(width: 10, height: 0)))
        XCTAssertNil(DayTimelineSwipe.direction(translation: CGSize(width: -10, height: 0)))
        XCTAssertNil(DayTimelineSwipe.direction(translation: .zero))
    }

    // MARK: - Above threshold, horizontal-dominant

    func test_leftSwipe_aboveThreshold_returnsForward() {
        // Negative dx = swipe-left = forward in time (toward next day).
        let dir = DayTimelineSwipe.direction(translation: CGSize(width: -40, height: 5))
        XCTAssertEqual(dir, .forward)
    }

    func test_rightSwipe_aboveThreshold_returnsBackward() {
        // Positive dx = swipe-right = backward in time.
        let dir = DayTimelineSwipe.direction(translation: CGSize(width: 40, height: -5))
        XCTAssertEqual(dir, .backward)
    }

    // MARK: - Vertical-dominant translations must NOT trigger a day step

    func test_verticalDominantTranslation_returnsNoStep() {
        // Diagonal swipe where height >> width — the user is trying to scroll,
        // not step days. The gesture must ignore.
        XCTAssertNil(DayTimelineSwipe.direction(translation: CGSize(width: 40, height: 120)))
        XCTAssertNil(DayTimelineSwipe.direction(translation: CGSize(width: -40, height: -120)))
    }

    func test_pureVerticalTranslation_returnsNoStep() {
        XCTAssertNil(DayTimelineSwipe.direction(translation: CGSize(width: 0, height: 200)))
        XCTAssertNil(DayTimelineSwipe.direction(translation: CGSize(width: 0, height: -200)))
    }

    // MARK: - Borderline: horizontal slightly larger than vertical → still step

    func test_horizontalDominant_evenWithSomeVerticalDrift_steps() {
        // |dx| = 60, |dy| = 30 → horizontal clearly dominates → step.
        XCTAssertEqual(
            DayTimelineSwipe.direction(translation: CGSize(width: -60, height: 30)),
            .forward
        )
    }
}
