import Foundation
import SwiftData

// MARK: - Shared enums (not versioned — these are pure value types)

enum ThrowTag: String, Codable, CaseIterable {
    case none = "None"
    case good = "Good throw"
    case notAThrow = "Not a throw"
    case edgeCase = "Edge case"
    case custom = "Custom"
}

enum ThrowType: String, Codable, CaseIterable {
    case backhand = "Backhand"
    case forehand = "Forehand"
}

enum ThrowHand: String, Codable, CaseIterable {
    case right = "RH"
    case left = "LH"

    var isLeft: Bool { self == .left }
}

// MARK: - Frozen V2 schema (for migration only)

/// Shipped through build 30. Adds `Disc.radius`, `ThrowData.launchAngle` over V1.
/// Superseded by V3 which adds `throwSeq` for firmware-dedupe.
///
/// Kept bare — do not reference from app code. Use the `ThrowData`/`Disc`
/// typealiases at the bottom of SchemaV3.swift instead.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [SchemaV2.Disc.self, SchemaV2.ThrowData.self]
    }

    @Model
    final class Disc {
        var brand: String
        var model: String
        var color: String
        var notes: String
        var createdAt: Date
        var radius: Float = 0.105

        @Relationship(inverse: \SchemaV2.ThrowData.disc) var throws_: [SchemaV2.ThrowData]

        init(brand: String, model: String, color: String = "", notes: String = "", radius: Float = 0.105) {
            self.brand = brand
            self.model = model
            self.color = color
            self.notes = notes
            self.radius = radius
            self.createdAt = Date()
            self.throws_ = []
        }
    }

    @Model
    final class ThrowData {
        var timestamp: Date
        var mph: Float
        var rpm: Float
        var peakG: Float
        var hyzer: Float
        var nose: Float
        var wobble: Float
        var durationMS: Int
        var isValid: Bool
        var notes: String
        var tag: String
        var throwType: String
        var throwHand: String
        var disc: SchemaV2.Disc?
        var rawSamples: Data?
        var releaseIdx: Int = 0
        var calRx: Float = 0
        var calRy: Float = 0
        var launchAngle: Float = 0

        init(timestamp: Date, mph: Float, rpm: Float, peakG: Float,
             hyzer: Float, nose: Float, wobble: Float,
             durationMS: Int, isValid: Bool, disc: SchemaV2.Disc? = nil,
             notes: String = "", tag: String = "None",
             throwType: String = "Backhand", throwHand: String = "RH") {
            self.timestamp = timestamp
            self.mph = mph
            self.rpm = rpm
            self.peakG = peakG
            self.hyzer = hyzer
            self.nose = nose
            self.wobble = wobble
            self.durationMS = durationMS
            self.isValid = isValid
            self.disc = disc
            self.notes = notes
            self.tag = tag
            self.throwType = throwType
            self.throwHand = throwHand
        }
    }
}
