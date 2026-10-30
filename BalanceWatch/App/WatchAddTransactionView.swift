import SwiftData
import SwiftUI

struct WatchAddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomCategory.createdAt)
    private var customCategories: [CustomCategory]

    private let transaction: FinanceTransaction?
    @State private var kind: TransactionKind
    @State private var amount: Double
    @State private var categoryName: String
    @State private var date: Date
    @State private var note: String

    init(transaction: FinanceTransaction? = nil) {
        self.transaction = transaction
        let initialKind = transaction?.kind ?? .expense
        _kind = State(initialValue: initialKind)
        _amount = State(initialValue: transaction?.amount ?? 0)
        _categoryName = State(initialValue: transaction?.categoryName
            ?? FinanceCategory.categories(for: initialKind)[0].name)
        _date = State(initialValue: transaction?.date ?? .now)
        _note = State(initialValue: transaction?.note ?? "")
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
        guard amount > 0 else { return }
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
                kind: kind
            ))
        }
        dismiss()
    }
}
