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
    /// v2: счёт (`accountId` на проводе), `nil` — «Без счёта».
    var accountID: String?
    /// v2: валюта суммы; `nil` — валюта счёта, иначе базовая.
    var currency: String?
    /// Идентификатор записи на проводе. `nil` у записей, созданных до v2:
    /// для них остаётся `id.uuidString`, чтобы не плодить дубли на сервере.
    var syncID: String?
    /// Незнакомые поля payload (теги, recurringId, …) — отправляются обратно как есть.
    var extraPayload: Data?

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
        accountID: String? = nil,
        currency: String? = nil,
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
        self.accountID = accountID
        self.currency = currency
        self.syncID = id.uuidString.lowercased()
        self.syncUpdatedAt = syncUpdatedAt
    }

    var wireID: String { syncID ?? id.uuidString }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRawValue) ?? .expense }
        set { kindRawValue = newValue.rawValue }
    }
}
