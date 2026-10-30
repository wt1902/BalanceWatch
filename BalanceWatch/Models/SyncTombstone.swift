import Foundation
import SwiftData

@Model
final class SyncTombstone {
    var id: UUID = UUID()
    var entity: String = ""
    var recordID: String = ""
    var updatedAt: Date = Date.now

    init(entity: String, recordID: String, updatedAt: Date = .now) {
        self.entity = entity
        self.recordID = recordID
        self.updatedAt = updatedAt
    }
}

struct SyncDeletionRecord: Codable, Identifiable {
    let id: UUID
    let entity: String
    let recordID: String
    let updatedAt: Date

    init(entity: String, recordID: String, updatedAt: Date = .now) {
        self.id = UUID()
        self.entity = entity
        self.recordID = recordID
        self.updatedAt = updatedAt
    }
}

enum SyncDeletionStore {
    private static let storageKey = "balance.server.deletionJournal.v1"
    private static let quarantineKey = "balance.server.deletionJournal.corrupt"
    private static let lock = NSLock()

    static func add(entity: String, recordID: String, updatedAt: Date = .now) {
        guard supportedEntities.contains(entity), UUID(uuidString:recordID) != nil else { return }
        lock.lock()
        defer { lock.unlock() }
        var records = loadUnlocked()
        records.removeAll { $0.entity == entity && $0.recordID == recordID }
        records.append(SyncDeletionRecord(entity:entity, recordID:recordID, updatedAt:updatedAt))
        saveUnlocked(records)
    }

    static func page(through cutoff: Date, offset: Int, limit: Int) -> [SyncDeletionRecord] {
        guard offset >= 0, limit > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        let records = loadUnlocked()
            .filter { $0.updatedAt <= cutoff && supportedEntities.contains($0.entity) && UUID(uuidString:$0.recordID) != nil }
            .sorted { $0.updatedAt < $1.updatedAt }
        guard offset < records.count else { return [] }
        return Array(records[offset..<min(offset + limit, records.count)])
    }

    static func remove(entity: String, recordID: String, through updatedAt: Date) {
        lock.lock()
        defer { lock.unlock() }
        var records = loadUnlocked()
        records.removeAll {
            $0.entity == entity && $0.recordID == recordID && $0.updatedAt <= updatedAt
        }
        saveUnlocked(records)
    }

    private static let supportedEntities = Set(["transaction", "category", "budget"])

    private static func loadUnlocked() -> [SyncDeletionRecord] {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey:storageKey) else { return [] }
        do {
            return try JSONDecoder().decode([SyncDeletionRecord].self, from:data)
        } catch {
            defaults.set(data, forKey:quarantineKey)
            defaults.removeObject(forKey:storageKey)
            return []
        }
    }

    private static func saveUnlocked(_ records: [SyncDeletionRecord]) {
        let defaults = UserDefaults.standard
        guard !records.isEmpty else {
            defaults.removeObject(forKey:storageKey)
            return
        }
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey:storageKey)
        }
    }
}

extension ModelContext {
    func deleteForSync(_ transaction: FinanceTransaction) {
        SyncDeletionStore.add(entity:"transaction", recordID:transaction.id.uuidString)
        delete(transaction)
    }

    func deleteForSync(_ category: CustomCategory) {
        SyncDeletionStore.add(entity:"category", recordID:category.id.uuidString)
        delete(category)
    }

    func deleteForSync(_ budget: MonthlyBudget) {
        SyncDeletionStore.add(entity:"budget", recordID:budget.id.uuidString)
        delete(budget)
    }
}
