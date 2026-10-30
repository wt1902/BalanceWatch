import Foundation
import Security
import SwiftData
import SwiftUI

private struct ServerUser: Codable { let id: String; let email: String }
private struct ServerSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: ServerUser
}
private struct ServerErrorEnvelope: Decodable {
    struct Detail: Decodable { let code: String; let message: String }
    let error: Detail
}
private struct SyncChange: Codable {
    let entity: String
    let id: String
    let deleted: Bool
    let updatedAt: Date
    let payload: Data?
    let version: Int64?
    let sequence: Int64?

    enum CodingKeys: String, CodingKey { case entity, id, deleted, updatedAt, payload, version, sequence }
    init(entity: String, id: String, deleted: Bool, updatedAt: Date, payload: Data? = nil, version: Int64? = nil, sequence: Int64? = nil) {
        self.entity = entity; self.id = id; self.deleted = deleted; self.updatedAt = updatedAt
        self.payload = payload; self.version = version; self.sequence = sequence
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        entity = try values.decode(String.self, forKey: .entity)
        id = try values.decode(String.self, forKey: .id)
        deleted = try values.decode(Bool.self, forKey: .deleted)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        version = try values.decodeIfPresent(Int64.self, forKey: .version)
        sequence = try values.decodeIfPresent(Int64.self, forKey: .sequence)
        if values.contains(.payload) {
            let object = try values.decode(JSONValue.self, forKey: .payload)
            payload = try ServerCoding.encoder.encode(object)
        } else { payload = nil }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(entity, forKey: .entity); try values.encode(id, forKey: .id)
        try values.encode(deleted, forKey: .deleted); try values.encode(updatedAt, forKey: .updatedAt)
        try values.encodeIfPresent(version, forKey: .version); try values.encodeIfPresent(sequence, forKey: .sequence)
        if let payload { try values.encode(ServerCoding.decoder.decode(JSONValue.self, from: payload), forKey: .payload) }
    }
}
private enum JSONValue: Codable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(Bool.self) { self = .bool(item) }
        else if let item = try? value.decode(Double.self) { self = .number(item) }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode([String: JSONValue].self) { self = .object(item) }
        else { self = .array(try value.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let item): try value.encode(item)
        case .number(let item): try value.encode(item)
        case .bool(let item): try value.encode(item)
        case .object(let item): try value.encode(item)
        case .array(let item): try value.encode(item)
        case .null: try value.encodeNil()
        }
    }
}
private struct SyncRequest: Encodable {
    let cursor: Int64
    let deviceId: String
    let changes: [SyncChange]
    let pull: Bool
}
private struct SyncResponse: Decodable {
    let cursor: Int64
    let changes: [SyncChange]
    let serverTime: Date
    let hasMore: Bool?
}

private struct TransactionPayload: Codable {
    let amount: Double; let date: Date; let note: String; let categoryName: String; let categoryIcon: String
    let categoryEmoji: String; let categoryColorName: String; let isBalanceAdjustment: Bool; let kindRawValue: String
}
private struct CategoryPayload: Codable {
    let name: String; let icon: String; let emoji: String; let colorName: String; let kindRawValue: String; let createdAt: Date
}
private struct BudgetPayload: Codable {
    let categoryName: String; let categoryIcon: String; let categoryEmoji: String; let limit: Double; let monthStart: Date
}

private enum ServerCoding {
    static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from:date))
        }
        return value
    }()
    static let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let regular = ISO8601DateFormatter()
            guard let date = fractional.date(from: text) ?? regular.date(from: text) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Invalid ISO-8601 date"
                )
            }
            return date
        }
        return value
    }()
}

enum ServerSyncError: LocalizedError {
    case invalidURL, insecureURL, response(String), notSignedIn
    var errorDescription: String? {
        switch self {
        case .invalidURL: "Укажите полный адрес сервера, например https://balance.example.com"
        case .insecureURL: "Для удалённого сервера требуется HTTPS. HTTP разрешён только для localhost."
        case .response(let message): message
        case .notSignedIn: "Сначала войдите в аккаунт."
        }
    }
}

@MainActor
final class ServerAccountStore: ObservableObject {
    static let shared = ServerAccountStore()
    @Published private(set) var signedInEmail: String?
    @Published private(set) var isBusy = false
    @Published private(set) var lastSyncAt: Date?
    @Published var message: String?

    private let defaults = UserDefaults.standard
    private var session: ServerSession?
    private let sessionKey = "balance.server.session"
    private let serverKey = "balance.server.url"
    private let syncBatchSize = 100

    var serverURL: String { defaults.string(forKey: serverKey) ?? "" }
    var isSignedIn: Bool { session != nil }

    private init() {
        if let data = KeychainStore.read(sessionKey), let value = try? ServerCoding.decoder.decode(ServerSession.self, from: data) {
            session = value; signedInEmail = value.user.email
        }
        lastSyncAt = defaults.object(forKey: "balance.server.lastSync") as? Date
    }

    func saveServer(_ value: String) throws {
        guard !isBusy else {
            throw ServerSyncError.response("Дождитесь завершения текущей синхронизации.")
        }
        let normalized = try normalizedServer(value)
        if normalized != serverURL { clearSession(); defaults.set(normalized, forKey: serverKey); clearSyncState() }
    }

    func register(email: String, password: String, context: ModelContext) async { await authenticate(path: "v1/auth/register", email: email, password: password, context: context) }
    func login(email: String, password: String, context: ModelContext) async { await authenticate(path: "v1/auth/login", email: email, password: password, context: context) }

    func logout() async {
        if let refresh = session?.refreshToken { _ = try? await request(path: "v1/auth/logout", body: ["refreshToken": refresh], authorized: false) as EmptyResponse }
        clearSession(); message = "Вы вышли из аккаунта."
    }

    func sync(context: ModelContext) async {
        guard session != nil, !isBusy else { return }
        isBusy = true; message = nil
        defer { isBusy = false }
        do {
            try context.save()
            let cutoff = Date.now
            let lastPush = defaults.object(forKey: pushKey()) as? Date ?? .distantPast
            let threshold = lastPush <= cutoff.addingTimeInterval(5)
                ? lastPush.addingTimeInterval(-5)
                : .distantPast
            let initialCursor = max(0, Int64(defaults.integer(forKey: cursorKey())))

            try await pushTransactions(context: context, after: threshold, through: cutoff, cursor: initialCursor)
            try await pushCategories(context: context, after: threshold, through: cutoff, cursor: initialCursor)
            try await pushBudgets(context: context, after: threshold, through: cutoff, cursor: initialCursor)
            try await pushTombstones(through: cutoff, cursor: initialCursor)
            try await pullChanges(context: context, cursor: initialCursor)

            defaults.set(cutoff, forKey: pushKey())
            lastSyncAt = .now; defaults.set(lastSyncAt, forKey: "balance.server.lastSync")
            message = "Синхронизация завершена."
        } catch { message = error.localizedDescription }
    }

    func resetSynchronization(context: ModelContext) async {
        guard !isBusy else { return }
        defaults.removeObject(forKey:cursorKey())
        defaults.removeObject(forKey:pushKey())
        message = "Запущена полная пересинхронизация…"
        await sync(context:context)
    }

    private func authenticate(path: String, email: String, password: String, context: ModelContext) async {
        guard !isBusy else { return }; isBusy = true; message = nil; defer { isBusy = false }
        do {
            let response: ServerSession = try await request(path: path, body: ["email":email, "password":password], authorized: false)
            session = response; signedInEmail = response.user.email
            try KeychainStore.write(ServerCoding.encoder.encode(response), key: sessionKey)
            message = "Вход выполнен. Запускаю синхронизацию…"
            isBusy = false; await sync(context: context)
        } catch { message = error.localizedDescription }
    }

    private func request<Response: Decodable, Body: Encodable>(path: String, body: Body, authorized: Bool, retry: Bool = true) async throws -> Response {
        if authorized { try await refreshIfNeeded() }
        let base = try normalizedServer(serverURL)
        guard let url = URL(string: base + "/" + path) else { throw ServerSyncError.invalidURL }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized, let token = session?.accessToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try ServerCoding.encoder.encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServerSyncError.response("Сервер не вернул HTTP-ответ.") }
        if http.statusCode == 401, authorized, retry { try await refreshSession(); return try await self.request(path:path, body:body, authorized:true, retry:false) }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? ServerCoding.decoder.decode(ServerErrorEnvelope.self, from: data)
            if path == "v1/sync", envelope?.error.code == "invalid_json" {
                throw ServerSyncError.response("Обновите Balance Server до версии из текущего архива приложения.")
            }
            throw ServerSyncError.response(envelope?.error.message ?? "Ошибка сервера: HTTP \(http.statusCode)")
        }
        if Response.self == EmptyResponse.self { return EmptyResponse() as! Response }
        return try ServerCoding.decoder.decode(Response.self, from: data)
    }

    private func refreshIfNeeded() async throws { if let session, session.expiresAt.timeIntervalSinceNow < 60 { try await refreshSession() } }
    private func refreshSession() async throws {
        guard let refresh = session?.refreshToken else { throw ServerSyncError.notSignedIn }
        let updated: ServerSession = try await request(path:"v1/auth/refresh", body:["refreshToken":refresh], authorized:false, retry:false)
        session = updated; signedInEmail = updated.user.email
        try KeychainStore.write(ServerCoding.encoder.encode(updated), key: sessionKey)
    }

    private func normalizedServer(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), let host = url.host, scheme == "https" || scheme == "http" else { throw ServerSyncError.invalidURL }
        if scheme == "http" && host != "localhost" && host != "127.0.0.1" && host != "::1" { throw ServerSyncError.insecureURL }
        return trimmed
    }

    private func clearSession() { session = nil; signedInEmail = nil; KeychainStore.delete(sessionKey) }
    private func clearSyncState() {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("balance.server.cursor.") || key.hasPrefix("balance.server.lastPush.") {
            defaults.removeObject(forKey: key)
        }
    }
    private func cursorKey() -> String { "balance.server.cursor.\(serverURL).\(session?.user.id ?? "anonymous")" }
    private func pushKey() -> String { "balance.server.lastPush.\(serverURL).\(session?.user.id ?? "anonymous")" }
    private func deviceID() -> String {
        if let value = defaults.string(forKey: "balance.server.deviceID") { return value }
        let value = UUID().uuidString; defaults.set(value, forKey: "balance.server.deviceID"); return value
    }

    private func pushTransactions(context: ModelContext, after threshold: Date, through cutoff: Date, cursor: Int64) async throws {
        var offset = 0
        while true {
            let lowerBound = threshold
            let upperBound = cutoff
            var descriptor = FetchDescriptor<FinanceTransaction>(
                predicate: #Predicate { item in
                    item.syncUpdatedAt >= lowerBound && item.syncUpdatedAt <= upperBound
                },
                sortBy: [SortDescriptor(\FinanceTransaction.syncUpdatedAt)]
            )
            descriptor.fetchLimit = syncBatchSize
            descriptor.fetchOffset = offset
            let items = try context.fetch(descriptor)
            guard !items.isEmpty else { break }
            let changes = try items.map { item in
                let value = TransactionPayload(amount:item.amount, date:item.date, note:item.note, categoryName:item.categoryName, categoryIcon:item.categoryIcon, categoryEmoji:item.categoryEmoji, categoryColorName:item.categoryColorName, isBalanceAdjustment:item.isBalanceAdjustment, kindRawValue:item.kindRawValue)
                return SyncChange(entity:"transaction", id:item.id.uuidString, deleted:false, updatedAt:item.syncUpdatedAt, payload:try ServerCoding.encoder.encode(value))
            }
            try await sendPush(changes, cursor: cursor)
            offset += items.count
            if items.count < syncBatchSize { break }
            await Task.yield()
        }
    }

    private func pushCategories(context: ModelContext, after threshold: Date, through cutoff: Date, cursor: Int64) async throws {
        var offset = 0
        while true {
            let lowerBound = threshold
            let upperBound = cutoff
            var descriptor = FetchDescriptor<CustomCategory>(
                predicate: #Predicate { item in
                    item.syncUpdatedAt >= lowerBound && item.syncUpdatedAt <= upperBound
                },
                sortBy: [SortDescriptor(\CustomCategory.syncUpdatedAt)]
            )
            descriptor.fetchLimit = syncBatchSize
            descriptor.fetchOffset = offset
            let items = try context.fetch(descriptor)
            guard !items.isEmpty else { break }
            let changes = try items.map { item in
                let value = CategoryPayload(name:item.name, icon:item.icon, emoji:item.emoji, colorName:item.colorName, kindRawValue:item.kindRawValue, createdAt:item.createdAt)
                return SyncChange(entity:"category", id:item.id.uuidString, deleted:false, updatedAt:item.syncUpdatedAt, payload:try ServerCoding.encoder.encode(value))
            }
            try await sendPush(changes, cursor: cursor)
            offset += items.count
            if items.count < syncBatchSize { break }
            await Task.yield()
        }
    }

    private func pushBudgets(context: ModelContext, after threshold: Date, through cutoff: Date, cursor: Int64) async throws {
        var offset = 0
        while true {
            let lowerBound = threshold
            let upperBound = cutoff
            var descriptor = FetchDescriptor<MonthlyBudget>(
                predicate: #Predicate { item in
                    item.syncUpdatedAt >= lowerBound && item.syncUpdatedAt <= upperBound
                },
                sortBy: [SortDescriptor(\MonthlyBudget.syncUpdatedAt)]
            )
            descriptor.fetchLimit = syncBatchSize
            descriptor.fetchOffset = offset
            let items = try context.fetch(descriptor)
            guard !items.isEmpty else { break }
            let changes = try items.map { item in
                let value = BudgetPayload(categoryName:item.categoryName, categoryIcon:item.categoryIcon, categoryEmoji:item.categoryEmoji, limit:item.limit, monthStart:item.monthStart)
                return SyncChange(entity:"budget", id:item.id.uuidString, deleted:false, updatedAt:item.syncUpdatedAt, payload:try ServerCoding.encoder.encode(value))
            }
            try await sendPush(changes, cursor: cursor)
            offset += items.count
            if items.count < syncBatchSize { break }
            await Task.yield()
        }
    }

    private func pushTombstones(through cutoff: Date, cursor: Int64) async throws {
        var offset = 0
        while true {
            let items = SyncDeletionStore.page(
                through:cutoff,
                offset:offset,
                limit:syncBatchSize
            )
            guard !items.isEmpty else { break }
            let changes = items.map { SyncChange(entity:$0.entity, id:$0.recordID, deleted:true, updatedAt:$0.updatedAt) }
            try await sendPush(changes, cursor: cursor)
            offset += items.count
            if items.count < syncBatchSize { break }
            await Task.yield()
        }
    }

    private func sendPush(_ changes: [SyncChange], cursor: Int64) async throws {
        guard !changes.isEmpty else { return }
        if changes.contains(where: { ($0.payload?.count ?? 0) > 256 * 1024 }) {
            throw ServerSyncError.response("Одна из операций содержит слишком большую заметку для синхронизации.")
        }
        let body = SyncRequest(cursor:cursor, deviceId:deviceID(), changes:changes, pull:false)
        if try ServerCoding.encoder.encode(body).count > 1_500_000 {
            guard changes.count > 1 else {
                throw ServerSyncError.response("Одна запись слишком велика для отправки на сервер.")
            }
            let middle = changes.count / 2
            try await sendPush(Array(changes[..<middle]), cursor:cursor)
            try await sendPush(Array(changes[middle...]), cursor:cursor)
            return
        }
        let _: SyncResponse = try await request(path:"v1/sync", body:body, authorized:true)
    }

    private func pullChanges(context: ModelContext, cursor initialCursor: Int64) async throws {
        var cursor = initialCursor
        while true {
            let body = SyncRequest(cursor:cursor, deviceId:deviceID(), changes:[], pull:true)
            let response: SyncResponse = try await request(path:"v1/sync", body:body, authorized:true)
            guard response.cursor >= cursor else {
                throw ServerSyncError.response("Сервер вернул некорректный курсор синхронизации.")
            }
            try apply(response.changes, context:context)
            try context.save()
            defaults.set(response.cursor, forKey:cursorKey())
            guard response.hasMore == true else { break }
            guard response.cursor > cursor else {
                throw ServerSyncError.response("Сервер не смог продолжить постраничную синхронизацию.")
            }
            cursor = response.cursor
            await Task.yield()
        }
    }

    private func apply(_ changes: [SyncChange], context: ModelContext) throws {
        for change in changes.sorted(by: { ($0.sequence ?? 0) < ($1.sequence ?? 0) }) {
            if let id = UUID(uuidString:change.id) {
                if change.deleted {
                    switch change.entity {
                    case "transaction": if let item = try transaction(id:id, context:context), item.syncUpdatedAt <= change.updatedAt { context.delete(item) }
                    case "category": if let item = try category(id:id, context:context), item.syncUpdatedAt <= change.updatedAt { context.delete(item) }
                    case "budget": if let item = try budget(id:id, context:context), item.syncUpdatedAt <= change.updatedAt { context.delete(item) }
                    default: break
                    }
                } else if let data = change.payload {
                    switch change.entity {
                    case "transaction":
                        guard let value = try? ServerCoding.decoder.decode(TransactionPayload.self, from:data) else { continue }
                        if let item = try transaction(id:id, context:context) { if item.syncUpdatedAt < change.updatedAt { update(item, value, change.updatedAt) } }
                        else { context.insert(FinanceTransaction(id:id, amount:value.amount, date:value.date, note:value.note, categoryName:value.categoryName, categoryIcon:value.categoryIcon, categoryEmoji:value.categoryEmoji, categoryColorName:value.categoryColorName, isBalanceAdjustment:value.isBalanceAdjustment, kind:TransactionKind(rawValue:value.kindRawValue) ?? .expense, syncUpdatedAt:change.updatedAt)) }
                    case "category":
                        guard let value = try? ServerCoding.decoder.decode(CategoryPayload.self, from:data) else { continue }
                        if let item = try category(id:id, context:context) { if item.syncUpdatedAt < change.updatedAt { update(item, value, change.updatedAt) } }
                        else { context.insert(CustomCategory(id:id, name:value.name, icon:value.icon, emoji:value.emoji, colorName:value.colorName, kind:TransactionKind(rawValue:value.kindRawValue) ?? .expense, createdAt:value.createdAt, syncUpdatedAt:change.updatedAt)) }
                    case "budget":
                        guard let value = try? ServerCoding.decoder.decode(BudgetPayload.self, from:data) else { continue }
                        if let item = try budget(id:id, context:context) { if item.syncUpdatedAt < change.updatedAt { update(item, value, change.updatedAt) } }
                        else { context.insert(MonthlyBudget(id:id, categoryName:value.categoryName, categoryIcon:value.categoryIcon, categoryEmoji:value.categoryEmoji, limit:value.limit, monthStart:value.monthStart, syncUpdatedAt:change.updatedAt)) }
                    default: break
                    }
                }
            }
            SyncDeletionStore.remove(entity:change.entity, recordID:change.id, through:change.updatedAt)
        }
    }

    private func transaction(id: UUID, context: ModelContext) throws -> FinanceTransaction? {
        let recordID = id
        var descriptor = FetchDescriptor<FinanceTransaction>(predicate:#Predicate { item in item.id == recordID })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func category(id: UUID, context: ModelContext) throws -> CustomCategory? {
        let recordID = id
        var descriptor = FetchDescriptor<CustomCategory>(predicate:#Predicate { item in item.id == recordID })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func budget(id: UUID, context: ModelContext) throws -> MonthlyBudget? {
        let recordID = id
        var descriptor = FetchDescriptor<MonthlyBudget>(predicate:#Predicate { item in item.id == recordID })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func update(_ item: FinanceTransaction, _ value: TransactionPayload, _ date: Date) { item.amount=value.amount; item.date=value.date; item.note=value.note; item.categoryName=value.categoryName; item.categoryIcon=value.categoryIcon; item.categoryEmoji=value.categoryEmoji; item.categoryColorName=value.categoryColorName; item.isBalanceAdjustment=value.isBalanceAdjustment; item.kindRawValue=value.kindRawValue; item.syncUpdatedAt=date }
    private func update(_ item: CustomCategory, _ value: CategoryPayload, _ date: Date) { item.name=value.name; item.icon=value.icon; item.emoji=value.emoji; item.colorName=value.colorName; item.kindRawValue=value.kindRawValue; item.createdAt=value.createdAt; item.syncUpdatedAt=date }
    private func update(_ item: MonthlyBudget, _ value: BudgetPayload, _ date: Date) { item.categoryName=value.categoryName; item.categoryIcon=value.categoryIcon; item.categoryEmoji=value.categoryEmoji; item.limit=value.limit; item.monthStart=value.monthStart; item.syncUpdatedAt=date }
}

private struct EmptyResponse: Codable {}
private enum KeychainStore {
    static func read(_ key: String) -> Data? {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"BalanceServer", kSecAttrAccount as String:key, kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        var result: AnyObject?; guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }; return result as? Data
    }
    static func write(_ data: Data, key: String) throws {
        delete(key)
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"BalanceServer", kSecAttrAccount as String:key, kSecValueData as String:data, kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw ServerSyncError.response("Не удалось сохранить сессию в Keychain.") }
    }
    static func delete(_ key: String) { let query:[String:Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"BalanceServer", kSecAttrAccount as String:key]; SecItemDelete(query as CFDictionary) }
}

@MainActor
struct ServerAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var account = ServerAccountStore.shared
    @State private var server = ServerAccountStore.shared.serverURL
    @State private var email = ServerAccountStore.shared.signedInEmail ?? ""
    @State private var password = ""

    var body: some View {
        Form {
            Section("Сервер") {
                TextField("https://balance.example.com", text:$server)
                    .serverTextEntryConfiguration()
                    Button("Сохранить адрес") { do { try account.saveServer(server); server = account.serverURL; account.message = "Адрес сохранён. Войдите заново." } catch { account.message = error.localizedDescription } }
                        .disabled(account.isBusy)
            }
            Section(account.isSignedIn ? "Аккаунт" : "Вход или регистрация") {
                if let value = account.signedInEmail { LabeledContent("Выполнен вход", value:value) }
                else {
                    TextField("Email", text:$email)
                        .serverTextEntryConfiguration()
                    SecureField("Пароль (минимум 8 символов)", text:$password)
                    Button("Войти") { Task { await account.login(email:email, password:password, context:modelContext) } }.disabled(server.isEmpty || email.isEmpty || password.isEmpty || account.isBusy)
                    Button("Зарегистрироваться") { Task { await account.register(email:email, password:password, context:modelContext) } }.disabled(server.isEmpty || email.isEmpty || password.count < 8 || account.isBusy)
                }
            }
            if account.isSignedIn {
                Section("Синхронизация") {
                    Button("Синхронизировать сейчас") { Task { await account.sync(context:modelContext) } }.disabled(account.isBusy)
                    Button("Полная пересинхронизация") { Task { await account.resetSynchronization(context:modelContext) } }
                        .disabled(account.isBusy)
                    if let date = account.lastSyncAt { LabeledContent("Последняя", value:date.formatted(date:.abbreviated, time:.shortened)) }
                    Button("Выйти", role:.destructive) { Task { await account.logout() } }
                        .disabled(account.isBusy)
                }
            }
            if account.isBusy { ProgressView() }
            if let message = account.message { Section { Text(message).font(.footnote).foregroundStyle(.secondary) } }
        }
        .navigationTitle("Сервер")
    }
}

private extension View {
    @ViewBuilder
    func serverTextEntryConfiguration() -> some View {
        #if os(macOS)
        self
        #else
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #endif
    }
}
