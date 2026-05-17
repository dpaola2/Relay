//
//  Haptics.swift
//  Relay
//
//  Thin wrapper over `UIImpactFeedbackGenerator(.light)` so the Now-screen
//  taps can fire a light haptic without coupling the view layer to UIKit
//  directly, and so the call site is testable via a `HapticFeedbackPlaying`
//  seam (Arch §7 Decision 7 / UX-002).
//
//  Per ADR-002, the protocol and concrete wrapper are `nonisolated` so test
//  spies (`@unchecked Sendable`) can substitute across actor boundaries.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The single message Relay sends to its haptic engine. A spy in
/// `RelayTests/Support/HapticsTests.swift` conforms to this to assert
/// the Now-screen buttons fire haptics on tap.
protocol HapticFeedbackPlaying: Sendable {
    func impactOccurred()
}

#if canImport(UIKit)
/// Production conformance over `UIImpactFeedbackGenerator(.light)`. The
/// generator is created once and reused; UIKit prepares it lazily.
final class UIKitLightImpactPlayer: HapticFeedbackPlaying, @unchecked Sendable {
    private let generator = UIImpactFeedbackGenerator(style: .light)

    func impactOccurred() {
        generator.impactOccurred()
    }
}
#endif

/// Light-impact haptic emitter used on the Now screen.
struct Haptics: Sendable {
    private let player: any HapticFeedbackPlaying

    init(player: any HapticFeedbackPlaying) {
        self.player = player
    }

    /// Fire one light-impact haptic. Safe to call from any actor.
    func light() {
        player.impactOccurred()
    }
}
