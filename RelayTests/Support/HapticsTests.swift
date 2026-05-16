//
//  HapticsTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M3: Now Screen)
//
//  Covers gameplan acceptance criterion:
//    - UX-002 (haptics): Each Now-screen button tap fires
//      `UIImpactFeedbackGenerator(.light)`.
//
//  We can't assert on the real haptic hardware in unit tests, so the haptics
//  helper must be testable via a thin protocol. This test asserts the
//  observable behavior: calling `Haptics.light()` invokes the underlying
//  generator's `impactOccurred()` exactly once. Stage 5 implements `Haptics`
//  as a wrapper that depends on a `HapticFeedbackPlaying` protocol so a spy
//  can be injected here.
//
//  Will FAIL until Stage 5 lands `Relay/Support/Haptics.swift`.
//

import XCTest
@testable import Relay

final class HapticsTests: XCTestCase {

    func test_lightImpact_invokesUnderlyingGeneratorExactlyOnce() {
        let spy = SpyHapticFeedbackPlayer()
        let haptics = Haptics(player: spy)

        haptics.light()

        XCTAssertEqual(spy.impactOccurredCallCount, 1)
    }

    func test_multipleLightImpacts_eachFireOnce() {
        let spy = SpyHapticFeedbackPlayer()
        let haptics = Haptics(player: spy)

        haptics.light()
        haptics.light()
        haptics.light()

        XCTAssertEqual(spy.impactOccurredCallCount, 3)
    }
}

// MARK: - Spy

/// Spy conforming to the `HapticFeedbackPlaying` boundary the app code will define.
/// Per ADR-002, mocks crossing actor boundaries use `@unchecked Sendable`.
final class SpyHapticFeedbackPlayer: HapticFeedbackPlaying, @unchecked Sendable {
    private(set) var impactOccurredCallCount = 0

    func impactOccurred() {
        impactOccurredCallCount += 1
    }
}
