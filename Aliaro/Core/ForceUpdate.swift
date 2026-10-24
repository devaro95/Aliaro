import Foundation
import Supabase

/// Aliaro's own compatibility number, the same on iOS and Android and
/// independent of store version numbers. Bump it ONLY in a release everyone
/// must have (then, once it's live in both stores, set `app_compat.min_compat`
/// to the new value). Releases without mandatory changes leave it alone.
let ALIARO_COMPAT = 1

/// The single row of the `app_compat` Supabase table.
private struct RemoteAppCompat: Decodable {
    let minCompat: Int?

    enum CodingKeys: String, CodingKey {
        case minCompat = "min_compat"
    }
}

/// Force update: `app_compat.min_compat` (Supabase, single row, public read)
/// is the minimum `ALIARO_COMPAT` allowed. While it's null nothing happens;
/// once Varo sets it (SQL), every install below it is blocked by
/// `ForceUpdateView` until it updates from the App Store.
///
/// Checked at launch, every time the app becomes active and live via
/// Realtime. The last known minimum is cached, so a device that was told to
/// update stays blocked offline too. Fails open: if the table can't be read
/// (or doesn't exist yet in a project), nobody is blocked.
@MainActor
final class ForceUpdate: ObservableObject {
    static let shared = ForceUpdate()

    /// True when this install is older than the minimum allowed.
    @Published private(set) var required: Bool
    /// Debug builds only: shows the update screen without a real minimum (People → Debug).
    @Published var debugPreview = false

    private enum Keys {
        static let cachedMin = "aliaro.forceUpdate.minCompat"
    }
    private let defaults = UserDefaults.standard
    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?

    private init() {
        let cached = UserDefaults.standard.object(forKey: Keys.cachedMin) as? Int
        required = ForceUpdate.isBelow(cached)
    }

    func start() async {
        await refresh()
        if channel == nil { await listenForChanges() }
    }

    /// Every time the app becomes active: catches a minimum set while it was in the background.
    func refresh() async {
        do {
            let rows: [RemoteAppCompat] = try await supabase
                .from("app_compat")
                .select("min_compat")
                .execute()
                .value
            let min = rows.first?.minCompat
            if let min { defaults.set(min, forKey: Keys.cachedMin) } else { defaults.removeObject(forKey: Keys.cachedMin) }
            let isRequired = ForceUpdate.isBelow(min)
            if isRequired && !required {
                Track.event("force_update_shown", ["min_compat": min, "compat": ALIARO_COMPAT])
            }
            required = isRequired
        } catch {
            print("⚠️ Could not fetch app_compat, keeping cached value (\(error))")
        }
    }

    private static func isBelow(_ min: Int?) -> Bool {
        guard let min else { return false }
        return ALIARO_COMPAT < min
    }

    private func listenForChanges() async {
        let newChannel = supabase.channel("sync-app-compat")
        let inserts = newChannel.postgresChange(InsertAction.self, schema: "public", table: "app_compat")
        let updates = newChannel.postgresChange(UpdateAction.self, schema: "public", table: "app_compat")
        let deletes = newChannel.postgresChange(DeleteAction.self, schema: "public", table: "app_compat")
        await newChannel.subscribe()
        channel = newChannel

        listenTask = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await _ in inserts { await self.refresh() } }
                group.addTask { for await _ in updates { await self.refresh() } }
                group.addTask { for await _ in deletes { await self.refresh() } }
            }
        }
    }
}
