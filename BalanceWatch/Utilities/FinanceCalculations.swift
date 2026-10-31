import Foundation

struct FinancePeriodSummary {
    let income: Double
    let expenses: Double
    var missing: Set<String> = []

    var balance: Double { income - expenses }
}

struct CategorySpending: Identifiable {
    let name: String
    let icon: String
    let emoji: String
    let colorName: String
    let amount: Double

    var id: String { name }
}

/// Финансовые правила (общие для экосистемы, см. docs/CONTRACT_V2.md §2–3).
/// Расчёты ведутся в целых сотых; общие итоги — в базовой валюте.
enum FinanceCalculations {
    /// Общий баланс: все операции (включая корректировки и будущие даты)
    /// плюс входящие минус исходящие части переводов — всё в базовой валюте.
    static func totalBalance(
        transactions: [LedgerEntry],
        transfers: [LedgerTransfer] = [],
        context: CurrencyContext
    ) -> MoneyTotal {
        var total = MoneyTotal()
        for item in transactions {
            let cents = Money.cents(item.amount)
            total.add(item.isIncome ? cents : -cents, context.currency(of: item), context.converter)
        }
        for transfer in transfers {
            total.add(Money.cents(transfer.incomingAmount), context.accountCurrency(transfer.toAccountID), context.converter)
            total.add(-Money.cents(transfer.amount), context.accountCurrency(transfer.fromAccountID), context.converter)
        }
        return total
    }

    /// Баланс счёта в его валюте, без конвертации.
    static func accountBalance(
        accountID: String,
        transactions: [LedgerEntry],
        transfers: [LedgerTransfer]
    ) -> Int64 {
        let key = accountID.lowercased()
        var cents: Int64 = 0
        for item in transactions where item.accountID?.lowercased() == key {
            let value = Money.cents(item.amount)
            cents += item.isIncome ? value : -value
        }
        for transfer in transfers {
            if transfer.toAccountID.lowercased() == key { cents += Money.cents(transfer.incomingAmount) }
            if transfer.fromAccountID.lowercased() == key { cents -= Money.cents(transfer.amount) }
        }
        return cents
    }

    /// «Без счёта»: операции без `accountId`, по валютам.
    static func unassignedBalances(
        transactions: [LedgerEntry],
        context: CurrencyContext
    ) -> [String: Int64] {
        var result: [String: Int64] = [:]
        for item in transactions where item.accountID == nil {
            let value = Money.cents(item.amount)
            result[context.currency(of: item), default: 0] += item.isIncome ? value : -value
        }
        return result
    }

    static func monthInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .month, for: date)
            ?? DateInterval(start: date, duration: 30 * 24 * 60 * 60)
    }

    /// Доходы и расходы периода `[начало, конец)` без корректировок, в базовой валюте.
    static func summary(
        transactions: [LedgerEntry],
        in interval: DateInterval,
        context: CurrencyContext
    ) -> FinancePeriodSummary {
        var income = MoneyTotal(), expenses = MoneyTotal()
        for item in transactions where contains(interval, item.date) && !item.isBalanceAdjustment {
            if item.isIncome { income.add(Money.cents(item.amount), context.currency(of: item), context.converter) }
            else { expenses.add(Money.cents(item.amount), context.currency(of: item), context.converter) }
        }
        return FinancePeriodSummary(
            income: income.value,
            expenses: expenses.value,
            missing: income.missing.union(expenses.missing)
        )
    }

    static func spendingByCategory(
        transactions: [FinanceTransaction],
        in interval: DateInterval,
        context: CurrencyContext
    ) -> [CategorySpending] {
        let expenses = transactions.filter {
            $0.kind == .expense
                && !$0.isBalanceAdjustment
                && contains(interval, $0.date)
        }
        let grouped = Dictionary(grouping: expenses, by: \FinanceTransaction.categoryName)

        return grouped.map { name, items in
            var total = MoneyTotal()
            for item in items { total.add(Money.cents(item.amount), context.currency(of: item), context.converter) }
            return CategorySpending(
                name: name,
                icon: items.first?.categoryIcon ?? "circle.fill",
                emoji: items.first?.categoryEmoji ?? "",
                colorName: items.first?.categoryColorName ?? "auto",
                amount: total.value
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    /// Полуоткрытый интервал: `DateInterval.contains` включает конец.
    static func contains(_ interval: DateInterval, _ date: Date) -> Bool {
        date >= interval.start && date < interval.end
    }
}
