import Foundation
import SwiftData

/// Original schema, shipped through build 9.
///
/// Differences from V2: `Disc` has no `radius`; `ThrowData` has no `launchAngle`.
/// Kept around so SwiftData can migrate existing on-device stores into V2 via
/// `OpenDiscMigrationPlan`. Do not reference these types from app code — they
/// exist purely for migration.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [SchemaV1.Disc.self, SchemaV1.ThrowData.self]
    }

    @Model
    final class Disc {
        var brand: String
        var model: String
        var color: String
        var notes: String
        var createdAt: Date

        @Relationship(inverse: \SchemaV1.ThrowData.disc) var throws_: [SchemaV1.ThrowData]

        init(brand: String, model: String, color: String = "", notes: String = "") {
            self.brand = brand
            self.model = model
            self.color = color
            self.notes = notes
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
        var disc: SchemaV1.Disc?
        var rawSamples: Data?
        var releaseIdx: Int = 0
        var calRx: Float = 0
        var calRy: Float = 0

        init(timestamp: Date, mph: Float, rpm: Float, peakG: Float,
             hyzer: Float, nose: Float, wobble: Float,
             durationMS: Int, isValid: Bool, disc: SchemaV1.Disc? = nil,
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
