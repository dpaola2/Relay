//
//  Item.swift
//  Relay
//
//  Created by Dave Paola on 5/16/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
