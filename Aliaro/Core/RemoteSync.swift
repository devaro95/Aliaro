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

    func fetchAll(familyID: UUID) async throws -> [Remote] {
        try await supabase
            .from(Remote.tableName)
            .select()
            .eq("family_id", value: familyID)
            .execute()
            .value
    }

    func push(_ record: Remote) async throws {
        try await supabase
            .from(Remote.tableName)
            .upsert(record)
            .execute()
    }

    func remove(id: UUID) async throws {
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
                            await MainActor.run { onUpsert(record) }
                        }
                    }
                }
                group.addTask {
                    for await change in updates {
                        if let record = Self.decodeRecord(change.record) {
                            await MainActor.run { onUpsert(record) }
                        }
                    }
                }
                group.addTask {
                    for await change in deletes {
                        if let id = Self.decodeDeletedID(change.oldRecord) {
                            await MainActor.run { onDelete(id) }
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
