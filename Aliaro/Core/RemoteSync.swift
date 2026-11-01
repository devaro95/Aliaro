import Foundation
import Supabase

/// Shared formatters for dates coming from Postgres
/// (timestamptz), which sometimes include a fractional second and sometimes don't.
enum AliaroDateFormatting {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Same format the server sends, so `decoder()` reads it back.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, valueEncoder in
            var container = valueEncoder.singleValueContainer()
            try container.encode(fractional.string(from: date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { valueDecoder in
            let container = try valueDecoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = fractional.date(from: string) { return date }
            if let date = plain.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(string)")
        }
        return decoder
    }
}

/// Classifies sync errors.
@MainActor
enum SyncErrors {
    /// Worth retrying later: no connection, timeout, server down, or the row
    /// it depends on isn't uploaded yet (foreign key). Anything else (no
    /// permission, a column missing, invalid data…) won't fix itself.
    nonisolated static func isRetryable(_ error: Error) -> Bool {
        if let postgrest = error as? PostgrestError {
            let code = postgrest.code ?? ""
            return code == "23503" || code.hasPrefix("08") || code.hasPrefix("57")
        }
        if error is URLError || error is CancellationError { return true }
        let domain = (error as NSError).domain
        return domain == NSURLErrorDomain || domain == "kCFErrorDomainCFNetwork"
    }

    /// Ids whose failure a form is already showing in its own dialog, so
    /// the general "couldn't save" notice isn't shown on top.
    static var claimed: Set<UUID> = []

    static func claim(_ id: UUID) { claimed.insert(id) }
}

/// Writes that couldn't reach Supabase (no connection…), kept on the device
/// and retried on every sync, so nothing created offline is lost.
///
/// Rules (so it can't cause trouble for the rest of the family):
/// - The row's id is created on the device and saved with `upsert`, so
///   retrying never duplicates it.
/// - A pending edit of a row that's no longer on the server is dropped:
///   someone deleted it, and that wins. Only rows never uploaded
///   (`isNew`) are kept until they're saved.
/// - Only errors worth retrying are queued (`SyncErrors.isRetryable`);
///   anything Supabase rejects is dropped and reported.
/// - Cleared when leaving the family (`clearAll`), so nothing reaches
///   another group.
@MainActor
enum PendingSync {
    struct Upsert: Codable {
        var json: Data
        var isNew: Bool
    }

    private struct Store: Codable {
        var upserts: [String: [String: Upsert]] = [:]
        var deletes: [String: [String]] = [:]
    }

    private static let key = "aliaro.pendingSync"
    private static var cache: Store?

    private static var store: Store {
        get {
            if let cache { return cache }
            let loaded = UserDefaults.standard.data(forKey: key)
                .flatMap { try? JSONDecoder().decode(Store.self, from: $0) } ?? Store()
            cache = loaded
            return loaded
        }
        set {
            cache = newValue
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key)
        }
    }

    static func upserts(_ table: String) -> [UUID: Upsert] {
        var result: [UUID: Upsert] = [:]
        for (id, value) in store.upserts[table] ?? [:] {
            if let uuid = UUID(uuidString: id) { result[uuid] = value }
        }
        return result
    }

    static func deletes(_ table: String) -> Set<UUID> {
        Set((store.deletes[table] ?? []).compactMap(UUID.init(uuidString:)))
    }

    static func setUpsert(_ table: String, id: UUID, _ value: Upsert?) {
        var current = store
        current.upserts[table, default: [:]][id.uuidString] = value
        store = current
    }

    static func setDelete(_ table: String, id: UUID, pending: Bool) {
        var current = store
        var ids = current.deletes[table] ?? []
        ids.removeAll { $0 == id.uuidString }
        if pending { ids.append(id.uuidString) }
        current.deletes[table] = ids
        store = current
    }

    static var isEmpty: Bool {
        store.upserts.values.allSatisfy(\.isEmpty) && store.deletes.values.allSatisfy(\.isEmpty)
    }

    static func clearAll() {
        store = Store()
    }
}

/// A row from a Supabase table with a flat shape (id + family_id + simple
/// fields), syncable with `RemoteSync`.
protocol FamilySynced: Codable, Identifiable where ID == UUID {
    static var tableName: String { get }
}

/// Syncs a Supabase table with the app: fetches all of the family's
/// records, listens for real-time inserts/edits/deletes from any
/// device in the group, and allows pushing or deleting its own records.
@MainActor
final class RemoteSync<Remote: FamilySynced> {
    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?
    /// Ids known to exist on the server (last fetch + real-time), to tell a
    /// new row from an edit when a save has to wait (see `PendingSync`).
    private var knownIDs: Set<UUID> = []
    private var knownLoaded = false
    /// Called when Supabase rejects a pending write on retry (it's dropped).
    var onRejected: ((Error) -> Void)?

    /// Rows per request. Supabase caps responses at 1000 rows by default, so
    /// we page until a short page arrives: callers prune local data against
    /// this result, and a truncated list would delete real records locally.
    private static var pageSize: Int { 1000 }

    func fetchAll(familyID: UUID) async throws -> [Remote] {
        var all: [Remote] = []
        var from = 0
        while true {
            let page: [Remote] = try await supabase
                .from(Remote.tableName)
                .select()
                .eq("family_id", value: familyID)
                .order("id")
                .range(from: from, to: from + Self.pageSize - 1)
                .execute()
                .value
            all.append(contentsOf: page)
            if page.count < Self.pageSize { break }
            from += Self.pageSize
        }
        knownIDs = Set(all.map(\.id))
        knownLoaded = true
        await retryPending()

        // What's still waiting to be uploaded wins over the server copy, so
        // the caller doesn't prune or overwrite it locally.
        let pendingDeletes = PendingSync.deletes(Remote.tableName)
        all.removeAll { pendingDeletes.contains($0.id) }
        let decoder = AliaroDateFormatting.decoder()
        for (id, pending) in PendingSync.upserts(Remote.tableName) {
            guard let record = try? decoder.decode(Remote.self, from: pending.json) else { continue }
            if let index = all.firstIndex(where: { $0.id == id }) {
                all[index] = record
            } else {
                all.append(record)
            }
        }
        return all
    }

    /// Saves the record (insert or update). If Supabase can't be reached,
    /// it's kept on the device and retried on the next sync; the error is
    /// rethrown either way so a form can tell the user.
    func push(_ record: Remote) async throws {
        do {
            try await upload(record)
            PendingSync.setUpsert(Remote.tableName, id: record.id, nil)
            knownIDs.insert(record.id)
        } catch {
            if SyncErrors.isRetryable(error), let json = try? AliaroDateFormatting.encoder().encode(record) {
                let previous = PendingSync.upserts(Remote.tableName)[record.id]
                // Before the first fetch we can't tell: treat it as new so it's never lost.
                let isNew = previous?.isNew ?? !(knownLoaded && knownIDs.contains(record.id))
                PendingSync.setUpsert(Remote.tableName, id: record.id, .init(json: json, isNew: isNew))
            }
            throw error
        }
    }

    /// Deletes the row. If Supabase can't be reached, the delete is kept on
    /// the device and retried on the next sync (meanwhile it stays hidden).
    func remove(id: UUID) async throws {
        PendingSync.setUpsert(Remote.tableName, id: id, nil)
        do {
            try await delete(id: id)
            PendingSync.setDelete(Remote.tableName, id: id, pending: false)
            knownIDs.remove(id)
        } catch {
            if SyncErrors.isRetryable(error) {
                PendingSync.setDelete(Remote.tableName, id: id, pending: true)
            }
            throw error
        }
    }

    /// Retries the writes waiting on this device. Pending edits of rows
    /// someone else deleted are dropped (their delete wins); rejected ones
    /// are dropped and reported. Still offline → they keep waiting.
    func retryPending() async {
        for id in PendingSync.deletes(Remote.tableName) {
            do {
                try await delete(id: id)
                PendingSync.setDelete(Remote.tableName, id: id, pending: false)
                knownIDs.remove(id)
            } catch where SyncErrors.isRetryable(error) {
                return // still offline: try again on the next sync
            } catch {
                PendingSync.setDelete(Remote.tableName, id: id, pending: false)
                onRejected?(error)
            }
        }
        let decoder = AliaroDateFormatting.decoder()
        for (id, pending) in PendingSync.upserts(Remote.tableName) {
            if !pending.isNew && knownLoaded && !knownIDs.contains(id) {
                PendingSync.setUpsert(Remote.tableName, id: id, nil)
                continue
            }
            guard let record = try? decoder.decode(Remote.self, from: pending.json) else {
                PendingSync.setUpsert(Remote.tableName, id: id, nil)
                continue
            }
            do {
                try await upload(record)
                PendingSync.setUpsert(Remote.tableName, id: id, nil)
                knownIDs.insert(id)
            } catch where SyncErrors.isRetryable(error) {
                if !((error as? PostgrestError)?.code == "23503") { return } // offline
            } catch {
                PendingSync.setUpsert(Remote.tableName, id: id, nil)
                onRejected?(error)
            }
        }
    }

    private func upload(_ record: Remote) async throws {
        try await supabase
            .from(Remote.tableName)
            .upsert(record)
            .execute()
    }

    private func delete(id: UUID) async throws {
        try await supabase
            .from(Remote.tableName)
            .delete()
            .eq("id", value: id)
            .execute()
    }

    /// Starts listening for real-time changes to this family for this
    /// table. Keeps listening until `stop()` is called.
    func start(
        familyID: UUID,
        onUpsert: @escaping (Remote) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) async {
        await stop()

        let newChannel = supabase.channel("sync-\(Remote.tableName)-\(familyID.uuidString)")
        let filter = "family_id=eq.\(familyID.uuidString)"

        let inserts = newChannel.postgresChange(InsertAction.self, schema: "public", table: Remote.tableName, filter: filter)
        let updates = newChannel.postgresChange(UpdateAction.self, schema: "public", table: Remote.tableName, filter: filter)
        let deletes = newChannel.postgresChange(DeleteAction.self, schema: "public", table: Remote.tableName, filter: filter)

        await newChannel.subscribe()
        channel = newChannel

        listenTask = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await change in inserts {
                        if let record = Self.decodeRecord(change.record) {
                            await MainActor.run { self.knownIDs.insert(record.id); onUpsert(record) }
                        }
                    }
                }
                group.addTask {
                    for await change in updates {
                        if let record = Self.decodeRecord(change.record) {
                            await MainActor.run { self.knownIDs.insert(record.id); onUpsert(record) }
                        }
                    }
                }
                group.addTask {
                    for await change in deletes {
                        if let id = Self.decodeDeletedID(change.oldRecord) {
                            await MainActor.run {
                                self.knownIDs.remove(id)
                                // Someone deleted it: a pending edit of it is dropped.
                                if PendingSync.upserts(Remote.tableName)[id]?.isNew == false {
                                    PendingSync.setUpsert(Remote.tableName, id: id, nil)
                                }
                                onDelete(id)
                            }
                        }
                    }
                }
            }
        }
    }

    func stop() async {
        listenTask?.cancel()
        listenTask = nil
        if let channel {
            await supabase.removeChannel(channel)
        }
        channel = nil
    }

    nonisolated private static func decodeRecord(_ record: [String: AnyJSON]) -> Remote? {
        guard let data = try? JSONEncoder().encode(record) else { return nil }
        return try? AliaroDateFormatting.decoder().decode(Remote.self, from: data)
    }

    nonisolated private static func decodeDeletedID(_ oldRecord: [String: AnyJSON]) -> UUID? {
        guard case let .string(idString)? = oldRecord["id"] else { return nil }
        return UUID(uuidString: idString)
    }
}
