import Foundation
import SwiftData

@Model
final class CustomCategory {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "star.fill"
    var emoji: String = ""
    var colorName: String = "indigo"
    var kindRawValue: String = "expense"
    var createdAt: Date = Date.now
    var syncUpdatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        emoji: String = "",
        colorName: String,
        kind: TransactionKind,
        createdAt: Date = .now,
        syncUpdatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.emoji = emoji
        self.colorName = colorName
        self.kindRawValue = kind.rawValue
        self.createdAt = createdAt
        self.syncUpdatedAt = syncUpdatedAt
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRawValue) ?? .expense }
        set { kindRawValue = newValue.rawValue }
    }

    var financeCategory: FinanceCategory {
        FinanceCategory(
            id: "custom-\(id.uuidString)",
            name: name,
            icon: icon,
            emoji: emoji,
            colorName: colorName
        )
    }
}
