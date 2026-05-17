//
//  Person.swift
//  Relay
//
//  The two people who can have sleep sessions logged in v1.
//

import Foundation

/// String-backed so SwiftData stores the value as a plain String, sidestepping
/// enum-migration friction (Arch §1.1 + §8.1).
enum Person: String, CaseIterable, Identifiable, Sendable {
    case dave = "dave"
    case bethany = "bethany"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dave: return "Dave"
        case .bethany: return "Bethany"
        }
    }
}
