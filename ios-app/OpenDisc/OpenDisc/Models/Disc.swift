import Foundation
import SwiftData

@Model
final class Disc {
    var brand: String
    var model: String
    var color: String
    var notes: String
    var createdAt: Date

    /// Effective disc radius in metres. Default 0.105 m (PDGA driver max).
    /// Used for advance-ratio calculation.
    var radius: Float = 0.105

    @Relationship(inverse: \ThrowData.disc) var throws_: [ThrowData]

    var displayName: String {
        "\(brand) \(model)"
    }

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
