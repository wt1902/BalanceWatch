import Foundation
import SwiftData
import SwiftUI

private enum WatchAnalyticsPeriod: String, CaseIterable, Identifiable {
    case month
    case threeMonths
    case year

    var id: String { rawValue }
    var title: String {
        switch self {
        case .month: "Месяц"
        case .threeMonths: "3 мес."
        case .year: "12 мес."
        }
    }

    func interval() -> DateInterval {
        let calendar = Calendar.current
        let current = calendar.dateInterval(of: .month, for: .now)
            ?? DateInterval(start: .now, duration: 30 * 86_400)
        let offset = self == .month ? 0 : (self == .threeMonths ? -2 : -11)
        let start = calendar.date(byAdding: .month, value: offset, to: current.start)
            ?? current.start
        return DateInterval(start: start, end: current.end)
    }
}

struct WatchAnalyticsView: View {
    @Query private var transactions: [FinanceTransaction]
    @Environment(\.currencyContext) private var currency
    @State private var period = WatchAnalyticsPeriod.month

    private var currencyCode: String { currency.base }
    private var interval: DateInterval { period.interval() }
    private var summary: FinancePeriodSummary {
        FinanceCalculations.summary(transactions: transactions, in: interval, context: currency)
    }
    private var spending: [CategorySpending] {
        Array(FinanceCalculations.spendingByCategory(
            transactions: transactions,
            in: interval,
            context: currency
        ).prefix(6))
    }
    private var savingsRate: Double {
        summary.income > 0 ? summary.balance / summary.income * 100 : 0
    }

    var body: some View {
        List {
            Picker("Период", selection: $period) {
                ForEach(WatchAnalyticsPeriod.allCases) { Text($0.title).tag($0) }
            }

            Section("Итоги") {
                metric("Доходы", summary.income, BalancePalette.income)
                metric("Расходы", summary.expenses, BalancePalette.expense)
                LabeledContent("Результат", value: summary.balance.formattedCurrency(code: currencyCode))
                LabeledContent(
                    "Сбережения",
                    value: savingsRate.formatted(.number.precision(.fractionLength(0))) + "%"
                )
                if let warning = currency.missingRateWarning(summary.missing) {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }

            Section("Категории") {
                if spending.isEmpty {
                    Text("Нет расходов").foregroundStyle(.secondary)
                } else {
                    ForEach(spending) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text((item.emoji.isEmpty ? "" : item.emoji + " ") + item.name)
                                    .lineLimit(1)
                                Spacer()
                                Text(item.amount.formattedCurrency(code: currencyCode))
                                    .font(.caption2)
                            }
                            ProgressView(
                                value: spending.first.map { item.amount / max($0.amount, 1) } ?? 0
                            )
                            .tint(tint(for: item))
                        }
                    }
                }
            }
        }
        .navigationTitle("Аналитика")
    }

    private func metric(_ title: String, _ amount: Double, _ tint: Color) -> some View {
        LabeledContent(title, value: amount.formattedCurrency(code: currencyCode))
            .foregroundStyle(tint)
    }

    private func tint(for item: CategorySpending) -> Color {
        item.colorName == "auto"
            ? FinanceCategory.find(named: item.name)?.tint ?? BalancePalette.forest
            : FinanceCategory.color(named: item.colorName)
    }
}

struct WatchTransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FinanceTransaction.date, order: .reverse)
    private var transactions: [FinanceTransaction]
    @Environment(\.currencyContext) private var currency
    @State private var selectedKind: TransactionKind?
    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var editing: FinanceTransaction?

    private var filtered: [FinanceTransaction] {
        transactions.filter {
            (selectedKind == nil || $0.kind == selectedKind)
                && (searchText.isEmpty
                    || $0.categoryName.localizedCaseInsensitiveContains(searchText)
                    || $0.note.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        List {
            Picker("Фильтр", selection: $selectedKind) {
                Text("Все").tag(TransactionKind?.none)
                Text("Расходы").tag(TransactionKind?.some(.expense))
                Text("Доходы").tag(TransactionKind?.some(.income))
            }

            ForEach(filtered) { transaction in
                Button {
                    editing = transaction
                } label: {
                    HStack {
                        CategoryIconView(
                            systemName: transaction.categoryIcon,
                            emoji: transaction.categoryEmoji,
                            tint: tint(transaction),
                            size: transaction.categoryEmoji.isEmpty ? 13 : 17,
                            containerSize: 30
                        )
                        VStack(alignment: .leading) {
                            Text(transaction.categoryName).lineLimit(1)
                            Text((transaction.kind == .income ? "+" : "−")
                                + transaction.amount.formattedCurrency(code: currency.currency(of: transaction)))
                                .font(.caption2)
                            if let title = currency.accountTitle(transaction.accountID) {
                                Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { modelContext.deleteForSync(transaction) } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Операции")
        .searchable(text: $searchText, prompt: "Поиск")
        .toolbar {
            Button { showingAdd = true } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $showingAdd) { WatchAddTransactionView() }
        .sheet(item: $editing) { WatchAddTransactionView(transaction: $0) }
    }

    private func tint(_ transaction: FinanceTransaction) -> Color {
        transaction.categoryColorName == "auto"
            ? FinanceCategory.find(named: transaction.categoryName)?.tint ?? BalancePalette.forest
            : FinanceCategory.color(named: transaction.categoryColorName)
    }
}

struct WatchBudgetsView: View {
    @Query private var budgets: [MonthlyBudget]
    @Query private var transactions: [FinanceTransaction]
    @Environment(\.currencyContext) private var currency
    @State private var showingEditor = false

    private var currencyCode: String { currency.base }

    private var interval: DateInterval {
        FinanceCalculations.monthInterval(containing: .now)
    }
    private var current: [MonthlyBudget] {
        budgets.filter { interval.contains($0.monthStart) }
    }
    private var spending: [String: Double] {
        Dictionary(uniqueKeysWithValues: FinanceCalculations.spendingByCategory(
            transactions: transactions,
            in: interval,
            context: currency
        ).map { ($0.name, $0.amount) })
    }

    var body: some View {
        List {
            if current.isEmpty {
                Text("Лимиты не заданы").foregroundStyle(.secondary)
            }
            ForEach(current) { budget in
                let spent = spending[budget.categoryName, default: 0]
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text((budget.categoryEmoji.isEmpty ? "" : budget.categoryEmoji + " ") + budget.categoryName)
                            .lineLimit(1)
                        Spacer()
                        Text(spent.formattedCurrency(code: currencyCode)).font(.caption2)
                    }
                    ProgressView(value: min(budget.limit > 0 ? spent / budget.limit : 0, 1))
                    Text("Лимит: \(budget.limit.formattedCurrency(code: currencyCode))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Бюджеты")
        .toolbar {
            Button { showingEditor = true } label: { Image(systemName: "pencil") }
        }
        .sheet(isPresented: $showingEditor) {
            WatchBudgetEditor(budgets: current, monthStart: interval.start)
        }
    }
}

private struct WatchBudgetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomCategory.createdAt) private var customCategories: [CustomCategory]
    let budgets: [MonthlyBudget]
    let monthStart: Date
    @State private var limits: [String: Double]

    init(budgets: [MonthlyBudget], monthStart: Date) {
        self.budgets = budgets
        self.monthStart = monthStart
        _limits = State(initialValue: Dictionary(uniqueKeysWithValues: budgets.map {
            ($0.categoryName, $0.limit)
        }))
    }

    private var categories: [FinanceCategory] {
        FinanceCategory.expenseCategories
            + customCategories.filter { $0.kind == .expense }.map(\.financeCategory)
    }

    var body: some View {
        Form {
            ForEach(categories) { category in
                TextField(category.name, value: binding(category.name), format: .number)
            }
            Button("Сохранить", action: save)
        }
        .navigationTitle("Лимиты")
    }

    private func binding(_ name: String) -> Binding<Double> {
        Binding(get: { limits[name, default: 0] }, set: { limits[name] = max(0, $0) })
    }

    private func save() {
        for category in categories {
            let value = Money.double(Money.cents(limits[category.name, default: 0]))
            let existing = budgets.first { $0.categoryName == category.name }
            if value > 0 {
                if let existing {
                    existing.limit = value
                    existing.syncUpdatedAt = .now
                } else {
                    modelContext.insert(MonthlyBudget(
                        categoryName: category.name,
                        categoryIcon: category.icon,
                        categoryEmoji: category.emoji,
                        limit: value,
                        monthStart: monthStart
                    ))
                }
            } else if let existing {
                modelContext.deleteForSync(existing)
            }
        }
        dismiss()
    }
}

struct WatchCategoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomCategory.createdAt) private var categories: [CustomCategory]
    @Query private var budgets: [MonthlyBudget]
    @State private var showingAdd = false
    @State private var editing: CustomCategory?

    var body: some View {
        List {
            if categories.isEmpty {
                Text("Нет своих категорий").foregroundStyle(.secondary)
            }
            ForEach(categories) { category in
                Button {
                    editing = category
                } label: {
                    HStack {
                        CategoryIconView(
                            systemName: category.icon,
                            emoji: category.emoji,
                            tint: FinanceCategory.color(named: category.colorName),
                            size: category.emoji.isEmpty ? 13 : 17,
                            containerSize: 30
                        )
                        Text(category.name)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        budgets.filter { $0.categoryName == category.name }
                            .forEach { modelContext.deleteForSync($0) }
                        modelContext.deleteForSync(category)
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Категории")
        .toolbar { Button { showingAdd = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingAdd) { WatchCategoryEditor() }
        .sheet(item: $editing) { WatchCategoryEditor(category: $0) }
    }
}

private struct WatchCategoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var transactions: [FinanceTransaction]
    @Query private var budgets: [MonthlyBudget]
    @Query private var customCategories: [CustomCategory]
    let category: CustomCategory?
    @State private var name: String
    @State private var kind: TransactionKind
    @State private var usesEmoji: Bool
    @State private var emoji: String
    @State private var icon: String
    @State private var colorName: String

    init(category: CustomCategory? = nil) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _kind = State(initialValue: category?.kind ?? .expense)
        _usesEmoji = State(initialValue: category?.emoji.isEmpty == false)
        _emoji = State(initialValue: category?.emoji ?? "⭐️")
        _icon = State(initialValue: category?.icon ?? "star.fill")
        _colorName = State(initialValue: category?.colorName ?? "indigo")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicate: Bool {
        let names = (FinanceCategory.expenseCategories + FinanceCategory.incomeCategories).map(\.name)
            + customCategories.filter { $0.id != category?.id }.map(\.name)
        return names.contains {
            $0.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    var body: some View {
        Form {
            TextField("Название", text: $name)
            if isDuplicate && !trimmedName.isEmpty {
                Text("Название уже занято").foregroundStyle(.red)
            }
            Picker("Тип", selection: $kind) {
                ForEach(TransactionKind.allCases) { Text($0.title).tag($0) }
            }
            .disabled(category != nil)
            Toggle("Эмодзи", isOn: $usesEmoji)
            if usesEmoji {
                TextField("Эмодзи", text: $emoji)
                Picker("Готовые", selection: $emoji) {
                    ForEach(CategoryDesignOptions.emojis, id: \.self) { Text($0).tag($0) }
                }
            } else {
                Picker("Иконка", selection: $icon) {
                    ForEach(CategoryDesignOptions.icons, id: \.self) { Text($0).tag($0) }
                }
            }
            Picker("Цвет", selection: $colorName) {
                ForEach(CategoryDesignOptions.colors, id: \.self) { Text($0).tag($0) }
            }
            Button("Сохранить", action: save)
                .disabled(trimmedName.isEmpty || isDuplicate)
        }
        .navigationTitle(category == nil ? "Новая" : "Изменить")
    }

    private func save() {
        guard !trimmedName.isEmpty && !isDuplicate else { return }
        let finalEmoji = usesEmoji ? emoji.first.map(String.init) ?? "" : ""
        if let category {
            let oldName = category.name
            category.name = trimmedName
            category.icon = icon
            category.emoji = finalEmoji
            category.colorName = colorName
            category.syncUpdatedAt = .now
            transactions.filter { $0.categoryName == oldName }.forEach {
                $0.categoryName = trimmedName
                $0.categoryIcon = icon
                $0.categoryEmoji = finalEmoji
                $0.categoryColorName = colorName
                $0.syncUpdatedAt = .now
            }
            budgets.filter { $0.categoryName == oldName }.forEach {
                $0.categoryName = trimmedName
                $0.categoryIcon = icon
                $0.categoryEmoji = finalEmoji
                $0.syncUpdatedAt = .now
            }
        } else {
            modelContext.insert(CustomCategory(
                name: trimmedName,
                icon: icon,
                emoji: finalEmoji,
                colorName: colorName,
                kind: kind
            ))
        }
        dismiss()
    }
}

struct WatchBalanceAdjustmentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var transactions: [FinanceTransaction]
    @Query private var transfers: [FinanceTransfer]
    @Environment(\.currencyContext) private var currency
    @StateObject private var account = ServerAccountStore.shared
    @State private var desired = 0.0
    @State private var note = ""

    private var currencyCode: String { currency.base }
    private var current: Double {
        FinanceCalculations.totalBalance(transactions: transactions, transfers: transfers, context: currency).value
    }
    private var difference: Double { desired - current }

    var body: some View {
        Form {
            LabeledContent("Сейчас", value: current.formattedCurrency(code: currencyCode))
            TextField("Фактически", value: $desired, format: .number)
            if abs(difference) >= 0.005 {
                LabeledContent("Разница", value: difference.formattedCurrency(code: currencyCode))
            }
            TextField("Комментарий", text: $note)
            Button("Сохранить", action: save).disabled(abs(difference) < 0.005)
        }
        .navigationTitle("Баланс")
        .onAppear { desired = current }
    }

    private func save() {
        guard abs(difference) >= 0.005 else { return }
        modelContext.insert(FinanceTransaction(
            amount: Money.double(Money.cents(abs(difference))),
            note: note.isEmpty ? "Ручная корректировка баланса" : note,
            categoryName: "Корректировка",
            categoryIcon: "slider.horizontal.3",
            categoryColorName: "indigo",
            isBalanceAdjustment: true,
            kind: difference > 0 ? .income : .expense,
            currency: account.supportsV2 ? currency.base : nil
        ))
        dismiss()
    }
}

struct WatchSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.currencyContext) private var currency
    @StateObject private var account = ServerAccountStore.shared
    @AppStorage("currencyCode") private var currencyCode = SupportedCurrency.RUB.rawValue
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @Query(filter: #Predicate<SyncRecord> { $0.entityName == "setting" && $0.recordID == "baseCurrency" })
    private var baseSetting: [SyncRecord]

    private var currencyCodes: [String] {
        let codes = SupportedCurrency.allCases.map(\.rawValue)
        return codes.contains(currency.base) ? codes : codes + [currency.base]
    }

    /// Базовая валюта: на сервере v2 — общая настройка `baseCurrency`,
    /// иначе — локальная настройка часов (как в v1).
    private var baseCurrency: Binding<String> {
        Binding(get: { currency.base }, set: { code in
            currencyCode = code
            guard account.supportsV2 || !baseSetting.isEmpty,
                  let payload = try? JSONSerialization.data(withJSONObject: ["value": code]) else { return }
            if let record = baseSetting.first {
                record.payload = payload
                record.syncUpdatedAt = .now
            } else {
                modelContext.insert(SyncRecord(entityName: "setting", recordID: SyncRecord.baseCurrencyKey, payload: payload, syncUpdatedAt: .now))
            }
        })
    }

    var body: some View {
        Form {
            Picker("Валюта", selection: baseCurrency) {
                ForEach(currencyCodes, id: \.self) { Text($0).tag($0) }
            }
            Picker("Тема", selection: $appTheme) {
                ForEach(AppTheme.allCases) { Text($0.title).tag($0.rawValue) }
            }
            NavigationLink {
                ServerAccountView()
            } label: {
                Label("Сервер", systemImage: "server.rack")
            }
            Label(
                "Локально; синхронизация через сервер",
                systemImage: "internaldrive.fill"
            )
            LabeledContent("Версия", value: "3.1.1")
        }
        .navigationTitle("Настройки")
    }
}
