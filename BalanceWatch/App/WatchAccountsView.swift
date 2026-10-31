import SwiftData
import SwiftUI

// Контракт v2 на часах: контекст валют, список счетов (только чтение)
// и выбор пространства (личное или общий бюджет).

private struct CurrencyContextKey: EnvironmentKey {
    static let defaultValue = CurrencyContext(base: SupportedCurrency.RUB.rawValue)
}

extension EnvironmentValues {
    /// Базовая валюта, валюты счетов и курсы текущего пространства.
    var currencyContext: CurrencyContext {
        get { self[CurrencyContextKey.self] }
        set { self[CurrencyContextKey.self] = newValue }
    }
}

/// Строит `CurrencyContext` из данных пространства и кладёт в окружение.
struct CurrencyContextProvider<Content: View>: View {
    @Query private var accounts: [FinanceAccount]
    @Query private var rates: [ExchangeRate]
    @Query(filter: #Predicate<SyncRecord> { $0.entityName == "setting" && $0.recordID == "baseCurrency" })
    private var baseSetting: [SyncRecord]
    @AppStorage("currencyCode") private var currencyCode = SupportedCurrency.RUB.rawValue
    @ViewBuilder let content: Content

    var body: some View {
        content.environment(\.currencyContext, CurrencyContext(
            base: baseSetting.first?.stringValue ?? currencyCode,
            accounts: accounts.map { ($0.syncID, $0.name, $0.currency) },
            quotes: rates.map(\.quote)
        ))
    }
}

struct WatchAccountsView: View {
    @Environment(\.currencyContext) private var currency
    @Query(sort: [SortDescriptor(\FinanceAccount.sortOrder), SortDescriptor(\FinanceAccount.name)])
    private var accounts: [FinanceAccount]
    @Query private var transactions: [FinanceTransaction]
    @Query private var transfers: [FinanceTransfer]

    private var total: MoneyTotal {
        FinanceCalculations.totalBalance(transactions: transactions, transfers: transfers, context: currency)
    }

    var body: some View {
        List {
            Section("Всего, \(currency.base)") {
                Text(total.value.formattedCurrency(code: currency.base)).font(.headline)
                if let warning = currency.missingRateWarning(total.missing) {
                    Label(warning, systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange)
                }
            }
            if accounts.isEmpty {
                Text("Счетов пока нет. Их создают на телефоне или компьютере.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(accounts) { account in
                row(
                    account.name + (account.isArchived ? " (архив)" : ""),
                    icon: account.icon,
                    tint: FinanceCategory.color(named: account.colorName),
                    cents: FinanceCalculations.accountBalance(accountID: account.syncID, transactions: transactions, transfers: transfers),
                    code: currency.accountCurrency(account.syncID)
                )
            }
            let unassigned = FinanceCalculations.unassignedBalances(transactions: transactions, context: currency)
            ForEach(unassigned.keys.sorted(), id: \.self) { code in
                row("Без счёта", icon: "tray.fill", tint: .gray, cents: unassigned[code] ?? 0, code: code)
            }
        }
        .navigationTitle("Счета")
    }

    private func row(_ title: String, icon: String, tint: Color, cents: Int64, code: String) -> some View {
        HStack {
            CategoryIconView(systemName: icon, emoji: "", tint: tint, size: 13, containerSize: 30)
            VStack(alignment: .leading) {
                Text(title).lineLimit(1)
                Text(Money.double(cents).formattedCurrency(code: code))
                    .font(.caption2).foregroundStyle(cents < 0 ? .red : .secondary)
            }
        }
    }
}

struct WatchLedgersView: View {
    @StateObject private var account = ServerAccountStore.shared
    @State private var ledgers: [ServerLedger] = []
    @State private var code = ""

    var body: some View {
        List {
            Section {
                choice("Личный", id: "", ledger: nil)
                ForEach(ledgers) { choice($0.name, id: $0.id, ledger: $0) }
            } footer: {
                Text("Данные каждого бюджета хранятся на часах отдельно.")
            }
            Section("Присоединиться") {
                TextField("Код приглашения", text: $code)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Присоединиться") {
                    Task {
                        if let ledger = await account.joinLedger(code: code) {
                            code = ""
                            if !ledgers.contains(ledger) { ledgers.append(ledger) }
                            account.selectLedger(ledger)
                        }
                    }
                }
                .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || account.isBusy)
            }
            if account.isBusy { ProgressView() }
            if let message = account.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("Бюджет")
        .task { if let value = await account.loadLedgers() { ledgers = value } }
    }

    private func choice(_ title: String, id: String, ledger: ServerLedger?) -> some View {
        Button {
            account.selectLedger(ledger)
        } label: {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                if account.ledgerID == id { Image(systemName: "checkmark") }
            }
        }
        .disabled(account.isBusy)
    }
}
