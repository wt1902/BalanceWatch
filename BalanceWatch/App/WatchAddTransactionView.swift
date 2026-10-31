import SwiftData
import SwiftUI

struct WatchAddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.currencyContext) private var currency
    @StateObject private var account = ServerAccountStore.shared
    @Query(sort: \CustomCategory.createdAt)
    private var customCategories: [CustomCategory]
    @Query(sort: [SortDescriptor(\FinanceAccount.sortOrder), SortDescriptor(\FinanceAccount.name)])
    private var accounts: [FinanceAccount]

    private let transaction: FinanceTransaction?
    @State private var kind: TransactionKind
    @State private var amount: Double
    @State private var categoryName: String
    @State private var date: Date
    @State private var note: String
    /// Пустая строка — «Без счёта».
    @State private var accountID: String

    init(transaction: FinanceTransaction? = nil) {
        self.transaction = transaction
        let initialKind = transaction?.kind ?? .expense
        _kind = State(initialValue: initialKind)
        _amount = State(initialValue: transaction?.amount ?? 0)
        _categoryName = State(initialValue: transaction?.categoryName
            ?? FinanceCategory.categories(for: initialKind)[0].name)
        _date = State(initialValue: transaction?.date ?? .now)
        _note = State(initialValue: transaction?.note ?? "")
        _accountID = State(initialValue: transaction?.accountID ?? "")
    }

    /// Активные счета; текущий счёт операции остаётся в списке, даже если
    /// он в архиве или удалён.
    private var accountChoices: [(id: String, title: String)] {
        var values = accounts.filter { !$0.isArchived }.map { ($0.syncID, $0.name) }
        if let current = transaction?.accountID,
           !values.contains(where: { $0.0.lowercased() == current.lowercased() }) {
            values.append((current, currency.accountTitle(current) ?? ""))
        }
        return [("", "Без счёта")] + values
    }

    private var showsAccounts: Bool {
        account.supportsV2 && (!accounts.isEmpty || transaction?.accountID != nil)
    }

    /// Валюта следует за счётом; у существующей операции без смены счёта
    /// валюта не меняется.
    private var effectiveCurrency: String {
        if let transaction, (transaction.accountID ?? "") == accountID {
            return currency.currency(of: transaction)
        }
        return accountID.isEmpty ? currency.base : currency.accountCurrency(accountID)
    }

    private var categories: [FinanceCategory] {
        var values = FinanceCategory.categories(for: kind)
            + customCategories.filter { $0.kind == kind }.map(\.financeCategory)
        if let transaction,
           !values.contains(where: { $0.name == transaction.categoryName }) {
            values.append(FinanceCategory(
                id: "archived-\(transaction.id)",
                name: transaction.categoryName,
                icon: transaction.categoryIcon,
                emoji: transaction.categoryEmoji,
                colorName: transaction.categoryColorName
            ))
        }
        return values
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Тип", selection: $kind) {
                    ForEach(TransactionKind.allCases) { Text($0.title).tag($0) }
                }
                .disabled(transaction?.isBalanceAdjustment == true)
                .onChange(of: kind) { _, newKind in
                    categoryName = FinanceCategory.categories(for: newKind)[0].name
                }

                TextField("Сумма", value: $amount, format: .number)

                if showsAccounts {
                    Picker("Счёт", selection: $accountID) {
                        ForEach(accountChoices, id: \.id) { Text($0.title).tag($0.id) }
                    }
                    LabeledContent("Валюта", value: effectiveCurrency)
                }

                Picker("Категория", selection: $categoryName) {
                    ForEach(categories) { category in
                        Text((category.emoji.isEmpty ? "" : category.emoji + " ") + category.name)
                            .tag(category.name)
                    }
                }
                .disabled(transaction?.isBalanceAdjustment == true)

                DatePicker("Дата", selection: $date, displayedComponents: .date)
                TextField("Заметка", text: $note)

                Button("Сохранить") {
                    save()
                }
                .disabled(amount <= 0)
            }
            .navigationTitle(transaction == nil ? "Операция" : "Изменить")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let amount = Money.double(Money.cents(amount))
        guard amount > 0 else { return }
        let newAccount = accountID.isEmpty ? nil : accountID
        let newCurrency = account.supportsV2 ? effectiveCurrency : nil
        let category = categories.first { $0.name == categoryName }
            ?? FinanceCategory.categories(for: kind)[0]
        if let transaction {
            transaction.amount = amount
            transaction.kind = kind
            transaction.categoryName = category.name
            transaction.categoryIcon = category.icon
            transaction.categoryEmoji = category.emoji
            transaction.categoryColorName = category.colorName
            transaction.date = date
            transaction.note = note
            if transaction.accountID != newAccount {
                transaction.accountID = newAccount
                transaction.currency = newCurrency
            }
            transaction.syncUpdatedAt = .now
        } else {
            modelContext.insert(FinanceTransaction(
                amount: amount,
                date: date,
                note: note,
                categoryName: category.name,
                categoryIcon: category.icon,
                categoryEmoji: category.emoji,
                categoryColorName: category.colorName,
                kind: kind,
                accountID: newAccount,
                currency: newCurrency
            ))
        }
        dismiss()
    }
}
