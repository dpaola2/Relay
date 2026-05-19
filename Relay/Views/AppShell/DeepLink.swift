//
//  DeepLink.swift
//  Relay
//
//  RELAY-9 — Parses the small set of URLs the widget's `widgetURL`
//  may deliver. Kept narrow on purpose: a Lookup not a router.
//

import Foundation

enum DeepLink: Equatable {
    case totals

    init?(url: URL) {
        guard url.scheme == "relay" else { return nil }
        switch url.host {
        case "totals": self = .totals
        default: return nil
        }
    }
}
