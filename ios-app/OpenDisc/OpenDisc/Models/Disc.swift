import Foundation
import SwiftData

@Model
final class Disc {
    var brand: String
    var model: String
    var color: String
    var notes: String
    var createdAt: Date

    @Relationship(inverse: \ThrowData.disc) var throws_: [ThrowData]

    var displayName: String {
        "\(brand) \(model)"
    }

    init(brand: String, model: String, color: String = "", notes: String = "") {
        self.brand = brand
        self.model = model
        self.color = color
        self.notes = notes
        self.createdAt = Date()
        self.throws_ = []
    }
}
