import Foundation
import SwiftData

enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: "Расход"
        case .income: "Доход"
        }
    }
}

@Model
final class FinanceTransaction {
    var id: UUID = UUID()
    var amount: Double = 0
    var date: Date = Date.now
    var note: String = ""
    var categoryName: String = ""
    var categoryIcon: String = "circle.fill"
    var categoryEmoji: String = ""
    var categoryColorName: String = "auto"
    var isBalanceAdjustment: Bool = false
    var kindRawValue: String = "expense"
    var syncUpdatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        amount: Double,
        date: Date = .now,
        note: String = "",
        categoryName: String,
        categoryIcon: String,
        categoryEmoji: String = "",
        categoryColorName: String = "auto",
        isBalanceAdjustment: Bool = false,
        kind: TransactionKind,
        syncUpdatedAt: Date = .now
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.note = note
        self.categoryName = categoryName
        self.categoryIcon = categoryIcon
        self.categoryEmoji = categoryEmoji
        self.categoryColorName = categoryColorName
        self.isBalanceAdjustment = isBalanceAdjustment
        self.kindRawValue = kind.rawValue
        self.syncUpdatedAt = syncUpdatedAt
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRawValue) ?? .expense }
        set { kindRawValue = newValue.rawValue }
    }
}
