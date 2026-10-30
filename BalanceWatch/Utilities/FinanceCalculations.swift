import Foundation

struct FinancePeriodSummary {
    let income: Double
    let expenses: Double

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

enum FinanceCalculations {
    static func totalBalance(transactions: [FinanceTransaction]) -> Double {
        transactions.reduce(0) { balance, transaction in
            balance + (transaction.kind == .income ? transaction.amount : -transaction.amount)
        }
    }

    static func monthInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .month, for: date)
            ?? DateInterval(start: date, duration: 30 * 24 * 60 * 60)
    }

    static func summary(
        transactions: [FinanceTransaction],
        in interval: DateInterval
    ) -> FinancePeriodSummary {
        let periodTransactions = transactions.filter {
            interval.contains($0.date) && !$0.isBalanceAdjustment
        }
        let income = periodTransactions
            .filter { $0.kind == .income }
            .reduce(0) { $0 + $1.amount }
        let expenses = periodTransactions
            .filter { $0.kind == .expense }
            .reduce(0) { $0 + $1.amount }

        return FinancePeriodSummary(income: income, expenses: expenses)
    }

    static func spendingByCategory(
        transactions: [FinanceTransaction],
        in interval: DateInterval
    ) -> [CategorySpending] {
        let expenses = transactions.filter {
            $0.kind == .expense
                && !$0.isBalanceAdjustment
                && interval.contains($0.date)
        }
        let grouped = Dictionary(grouping: expenses, by: \FinanceTransaction.categoryName)

        return grouped.map { name, items in
            CategorySpending(
                name: name,
                icon: items.first?.categoryIcon ?? "circle.fill",
                emoji: items.first?.categoryEmoji ?? "",
                colorName: items.first?.categoryColorName ?? "auto",
                amount: items.reduce(0) { $0 + $1.amount }
            )
        }
        .sorted { $0.amount > $1.amount }
    }
}
