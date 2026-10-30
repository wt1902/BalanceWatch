import SwiftData
import SwiftUI

struct WatchRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FinanceTransaction.date, order: .reverse)
    private var transactions: [FinanceTransaction]
    @AppStorage("currencyCode") private var currencyCode = SupportedCurrency.RUB.rawValue
    @State private var showingAddTransaction = false

    private var monthSummary: FinancePeriodSummary {
        FinanceCalculations.summary(
            transactions: transactions,
            in: FinanceCalculations.monthInterval(containing: .now)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Общий баланс")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(FinanceCalculations.totalBalance(transactions: transactions)
                            .formattedCurrency(code: currencyCode))
                            .font(.title3.bold())
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        LinearGradient(
                            colors: [.indigo, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .foregroundStyle(.white)

                    HStack(spacing: 8) {
                        watchMetric(
                            title: "Доходы",
                            amount: monthSummary.income,
                            tint: .green
                        )
                        watchMetric(
                            title: "Расходы",
                            amount: monthSummary.expenses,
                            tint: .red
                        )
                    }

                    Button {
                        showingAddTransaction = true
                    } label: {
                        Label("Добавить операцию", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    VStack(spacing: 4) {
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
                                        + transaction.amount.formattedCurrency(code: currencyCode))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(transaction.kind == .income ? .green : .secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Баланс")
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

    private func watchMetric(title: String, amount: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(amount.formattedCurrency(code: currencyCode))
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func transactionTint(_ transaction: FinanceTransaction) -> Color {
        if transaction.categoryColorName == "auto" {
            return FinanceCategory.find(named: transaction.categoryName)?.tint ?? .indigo
        }
        return FinanceCategory.color(named: transaction.categoryColorName)
    }
}
