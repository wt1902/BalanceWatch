import Foundation

/// Денежная арифметика контракта v2 (§0, §2): суммы — целые сотые,
/// курсы — десятичные строки, округление до сотых половиной от нуля.
/// Файл не зависит от SwiftUI/SwiftData.
enum Money {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Число с провода → целые сотые (лишние знаки округляются).
    static func cents(_ value: Double) -> Int64 {
        guard value.isFinite else { return 0 }
        let decimal = Decimal(string: String(value), locale: posix) ?? Decimal(value)
        return rounded(decimal * 100)
    }

    static func double(_ cents: Int64) -> Double { Double(cents) / 100 }

    /// Курс из строки: только цифры и не более одной точки, больше нуля.
    static func rate(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.filter({ $0 == "." }).count <= 1,
              trimmed.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              trimmed.first != ".", trimmed.last != ".",
              let value = Decimal(string: trimmed, locale: posix), value > 0
        else { return nil }
        return value
    }

    /// `cents · rate` (или `cents / rate` для обратной пары), округлено до сотых.
    static func convert(_ cents: Int64, rate: Decimal, inverse: Bool) -> Int64 {
        let value = Decimal(cents)
        return rounded(inverse ? value / rate : value * rate)
    }

    private static func rounded(_ value: Decimal) -> Int64 {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, 0, .plain) // половина — от нуля
        return NSDecimalNumber(decimal: result).int64Value
    }
}

struct RateQuote {
    let from: String
    let to: String
    let rate: String
    let date: Date
    let updatedAt: Date
}

/// Перевод сумм в базовую валюту по последнему курсу на дату расчёта.
struct CurrencyConverter {
    let base: String
    private var best: [String: (rate: Decimal, inverse: Bool, date: Date, updatedAt: Date)] = [:]

    init(base: String, quotes: [RateQuote], asOf: Date) {
        let base = base.uppercased()
        self.base = base
        for quote in quotes where quote.date <= asOf {
            let from = quote.from.uppercased(), to = quote.to.uppercased()
            guard from != to, let rate = Money.rate(quote.rate) else { continue }
            let other: String, inverse: Bool
            if to == base { other = from; inverse = false }
            else if from == base { other = to; inverse = true }
            else { continue }
            if let current = best[other] {
                // Последняя по дате; при равной дате прямая пара важнее
                // обратной; затем — более поздний updatedAt.
                let newer = (quote.date, inverse ? 0 : 1, quote.updatedAt)
                let old = (current.date, current.inverse ? 0 : 1, current.updatedAt)
                guard newer > old else { continue }
            }
            best[other] = (rate, inverse, quote.date, quote.updatedAt)
        }
    }

    /// `nil` — нет курса.
    func toBase(_ cents: Int64, from currency: String) -> Int64? {
        let code = currency.uppercased()
        if code == base || cents == 0 { return cents }
        guard let quote = best[code] else { return nil }
        return Money.convert(cents, rate: quote.rate, inverse: quote.inverse)
    }
}

protocol LedgerEntry {
    var amount: Double { get }
    var isIncome: Bool { get }
    var isBalanceAdjustment: Bool { get }
    var date: Date { get }
    var accountID: String? { get }
    var currency: String? { get }
}

protocol LedgerTransfer {
    var fromAccountID: String { get }
    var toAccountID: String { get }
    var amount: Double { get }
    var incomingAmount: Double { get }
}

/// Сумма в базовой валюте и валюты, для которых не нашлось курса.
struct MoneyTotal {
    var cents: Int64 = 0
    var missing: Set<String> = []

    var value: Double { Money.double(cents) }

    mutating func add(_ cents: Int64, _ currency: String, _ converter: CurrencyConverter) {
        if let converted = converter.toBase(cents, from: currency) { self.cents += converted }
        else { missing.insert(currency.uppercased()) }
    }
}

/// Всё, что нужно для расчётов в базовой валюте: базовая валюта,
/// валюты и названия счетов, курсы.
struct CurrencyContext {
    let converter: CurrencyConverter
    private let accountCurrencies: [String: String]
    private let accountNames: [String: String]

    var base: String { converter.base }

    init(base: String, accounts: [(id: String, name: String, currency: String)] = [], quotes: [RateQuote] = [], asOf: Date = .now) {
        let base = base.uppercased()
        converter = CurrencyConverter(base: base, quotes: quotes, asOf: asOf)
        var currencies: [String: String] = [:], names: [String: String] = [:]
        for account in accounts {
            let key = account.id.lowercased()
            currencies[key] = account.currency.isEmpty ? base : account.currency.uppercased()
            names[key] = account.name
        }
        accountCurrencies = currencies
        accountNames = names
    }

    /// Валюта счёта; удалённый счёт или пустая валюта — базовая.
    func accountCurrency(_ id: String?) -> String {
        guard let id else { return base }
        return accountCurrencies[id.lowercased()] ?? base
    }

    /// `currency`, иначе валюта счёта, иначе базовая.
    func currency(of entry: LedgerEntry) -> String {
        if let code = entry.currency, !code.isEmpty { return code.uppercased() }
        return accountCurrency(entry.accountID)
    }

    /// Название счёта, «Удалённый счёт» или `nil` для «Без счёта».
    func accountTitle(_ id: String?) -> String? {
        guard let id else { return nil }
        return accountNames[id.lowercased()] ?? "Удалённый счёт"
    }

    func missingRateWarning(_ missing: Set<String>) -> String? {
        guard !missing.isEmpty else { return nil }
        return missing.sorted().map { "нет курса \($0)→\(base)" }.joined(separator: ", ")
    }
}
