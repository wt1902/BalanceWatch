import Foundation
import SwiftData

@Model
final class MonthlyBudget {
    var id: UUID = UUID()
    var categoryName: String = ""
    var categoryIcon: String = "circle.fill"
    var categoryEmoji: String = ""
    var limit: Double = 0
    var monthStart: Date = Date.now
    var syncUpdatedAt: Date = Date.now
    var syncID: String?
    var extraPayload: Data?

    init(
        id: UUID = UUID(),
        categoryName: String,
        categoryIcon: String,
        categoryEmoji: String = "",
        limit: Double,
        monthStart: Date,
        syncUpdatedAt: Date = .now
    ) {
        self.id = id
        self.categoryName = categoryName
        self.categoryIcon = categoryIcon
        self.categoryEmoji = categoryEmoji
        self.limit = limit
        self.monthStart = monthStart
        self.syncID = id.uuidString.lowercased()
        self.syncUpdatedAt = syncUpdatedAt
    }

    var wireID: String { syncID ?? id.uuidString }
}
