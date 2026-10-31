import Foundation
import SwiftData

// Сущности контракта v2 (docs/CONTRACT_V2.md). Часы их только читают:
// создают и меняют их телефон и десктоп. `syncID` — id записи на проводе,
// `extraPayload` — незнакомые поля payload.

@Model
final class FinanceAccount {
    var syncID: String = ""
    var name: String = ""
    var kindRawValue: String = "other"
    var icon: String = "creditcard.fill"
    var colorName: String = "indigo"
    /// Пустая строка — базовая валюта.
    var currency: String = ""
    var createdAt: Date = Date.now
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var extraPayload: Data?
    var syncUpdatedAt: Date = Date.now

    init(syncID: String, syncUpdatedAt: Date) {
        self.syncID = syncID
        self.syncUpdatedAt = syncUpdatedAt
    }

    var key: String { syncID.lowercased() }
}

@Model
final class FinanceTransfer {
    var syncID: String = ""
    var fromAccountID: String = ""
    var toAccountID: String = ""
    var amount: Double = 0
    /// `nil` — равна `amount`.
    var toAmount: Double?
    var date: Date = Date.now
    var note: String = ""
    var extraPayload: Data?
    var syncUpdatedAt: Date = Date.now

    init(syncID: String, syncUpdatedAt: Date) {
        self.syncID = syncID
        self.syncUpdatedAt = syncUpdatedAt
    }
}

@Model
final class ExchangeRate {
    var syncID: String = ""
    var from: String = ""
    var to: String = ""
    /// Десятичная строка, сколько единиц `to` стоит одна единица `from`.
    var rate: String = ""
    var date: Date = Date.now
    var extraPayload: Data?
    var syncUpdatedAt: Date = Date.now

    init(syncID: String, syncUpdatedAt: Date) {
        self.syncID = syncID
        self.syncUpdatedAt = syncUpdatedAt
    }

    var quote: RateQuote { RateQuote(from: from, to: to, rate: rate, date: date, updatedAt: syncUpdatedAt) }
}

/// Записи, которые часы хранят без разбора: `recurring`, `goal`, `debt`,
/// `attachment`, `setting`. Payload хранится целиком, поэтому все поля сохраняются.
@Model
final class SyncRecord {
    /// Не `entity`: так называется встроенное свойство CoreData, и предикат
    /// по нему ломает SQL-запрос SwiftData.
    var entityName: String = ""
    var recordID: String = ""
    var payload: Data = Data()
    var syncUpdatedAt: Date = Date.now

    init(entityName: String, recordID: String, payload: Data, syncUpdatedAt: Date) {
        self.entityName = entityName
        self.recordID = recordID
        self.payload = payload
        self.syncUpdatedAt = syncUpdatedAt
    }

    static let storedEntities: Set<String> = ["recurring", "goal", "debt", "attachment", "setting"]
    static let baseCurrencyKey = "baseCurrency"

    /// Значение `setting` (`{"value": "USD"}`), если это строка.
    var stringValue: String? {
        (try? JSONSerialization.jsonObject(with: payload) as? [String: Any])?["value"] as? String
    }
}

extension FinanceTransaction: LedgerEntry {
    var isIncome: Bool { kind == .income }
}

extension FinanceTransfer: LedgerTransfer {
    var incomingAmount: Double { toAmount ?? amount }
}
