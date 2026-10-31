import SwiftData
import SwiftUI

struct WatchRootView: View {
    var body: some View {
        CurrencyContextProvider { WatchHomeView() }
    }
}

private struct WatchHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.currencyContext) private var currency
    @StateObject private var account = ServerAccountStore.shared
    @Query(sort: \FinanceTransaction.date, order: .reverse)
    private var transactions: [FinanceTransaction]
    @Query private var transfers: [FinanceTransfer]
    @State private var showingAddTransaction = false

    private var currencyCode: String { currency.base }
    private var total: MoneyTotal {
        FinanceCalculations.totalBalance(transactions: transactions, transfers: transfers, context: currency)
    }
    private var monthSummary: FinancePeriodSummary {
        FinanceCalculations.summary(
            transactions: transactions,
            in: FinanceCalculations.monthInterval(containing: .now),
            context: currency
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: "wallet.bifold")
                                .font(.caption2.weight(.semibold))
                            Text("Общий баланс")
                                .font(.caption)
                        }
                        .foregroundStyle(BalancePalette.mint.opacity(0.85))
                        Text(total.value.formattedCurrency(code: currencyCode))
                            .font(.title3.bold())
                            .minimumScaleFactor(0.7)
                        if let warning = currency.missingRateWarning(total.missing.union(monthSummary.missing)) {
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.caption2)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        LinearGradient(
                            colors: [BalancePalette.cardTop, BalancePalette.cardBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .foregroundStyle(.white)

                    HStack(spacing: 8) {
                        watchMetric(
                            title: "Доходы",
                            symbol: "arrow.down.left",
                            amount: monthSummary.income,
                            tint: BalancePalette.income
                        )
                        watchMetric(
                            title: "Расходы",
                            symbol: "arrow.up.right",
                            amount: monthSummary.expenses,
                            tint: BalancePalette.expense
                        )
                    }

                    Button {
                        showingAddTransaction = true
                    } label: {
                        Label("Добавить операцию", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BalancePalette.forest)

                    VStack(spacing: 4) {
                        if account.supportsV2 {
                            NavigationLink {
                                WatchAccountsView()
                            } label: {
                                Label("Счета", systemImage: "creditcard")
                            }
                        }
                        NavigationLink {
                            WatchAnalyticsView()
                        } label: {
                            Label("Аналитика", systemImage: "chart.xyaxis.line")
                        }
                        NavigationLink {
                            WatchTransactionsView()
                        } label: {
                            Label("Все операции", systemImage: "list.bullet.rectangle")
                        }
                        NavigationLink {
                            WatchBudgetsView()
                        } label: {
                            Label("Бюджеты", systemImage: "target")
                        }
                        NavigationLink {
                            WatchCategoriesView()
                        } label: {
                            Label("Категории", systemImage: "square.grid.2x2")
                        }
                        NavigationLink {
                            WatchBalanceAdjustmentView()
                        } label: {
                            Label("Корректировка", systemImage: "slider.horizontal.3")
                        }
                        NavigationLink {
                            WatchSettingsView()
                        } label: {
                            Label("Настройки", systemImage: "gearshape")
                        }
                    }

                    if !transactions.isEmpty {
                        Text("Последние")
                            .font(.headline)
                        ForEach(transactions.prefix(4)) { transaction in
                            HStack(spacing: 8) {
                                CategoryIconView(
                                    systemName: transaction.categoryIcon,
                                    emoji: transaction.categoryEmoji,
                                    tint: transactionTint(transaction),
                                    size: transaction.categoryEmoji.isEmpty ? 13 : 17,
                                    containerSize: 30
                                )
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(transaction.categoryName)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text((transaction.kind == .income ? "+" : "−")
                                        + transaction.amount.formattedCurrency(code: currency.currency(of: transaction)))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(transaction.kind == .income ? BalancePalette.income : .secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(account.ledgerID.isEmpty ? "Баланс" : account.ledgerName)
            .sheet(isPresented: $showingAddTransaction) {
                WatchAddTransactionView()
            }
        }
        .task {
            while !Task.isCancelled {
                await ServerAccountStore.shared.sync(context: modelContext)
                try? await Task.sleep(nanoseconds: 120_000_000_000)
            }
        }
    }

    private func watchMetric(title: String, symbol: String, amount: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(TintedIconLabelStyle(tint: tint))
            Text(amount.formattedCurrency(code: currencyCode))
                .font(.caption.bold())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
    }

    private func transactionTint(_ transaction: FinanceTransaction) -> Color {
        if transaction.categoryColorName == "auto" {
            return FinanceCategory.find(named: transaction.categoryName)?.tint ?? BalancePalette.forest
        }
        return FinanceCategory.color(named: transaction.categoryColorName)
    }
}

/// Иконка метрики в цвете метрики, подпись — вторичным цветом.
private struct TintedIconLabelStyle: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}
