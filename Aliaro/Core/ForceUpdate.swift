import Foundation
import Supabase

/// Legacy compatibility number (apps <= 1.3.1 only check this). Since 1.3.2
/// the force update goes by build number; this stays at 3 for good, so
/// `min_compat = 3` (dashboard: «bloquear versiones antiguas») blocks every
/// install up to 1.3.1 without touching 1.3.2+.
let ALIARO_COMPAT = 3

/// This install's build number (CFBundleVersion), compared with `app_compat.min_build_ios`.
private let APP_BUILD = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0

/// The single row of the `app_compat` Supabase table.
private struct RemoteAppCompat: Decodable {
    let minCompat: Int?
    let minBuild: Int?

    enum CodingKeys: String, CodingKey {
        case minCompat = "min_compat"
        case minBuild = "min_build_ios"
    }
}

/// Force update: `app_compat` (Supabase, single row, public read) holds the
/// minimum allowed. Since 1.3.2 Varo sets `min_build_ios` (minimum
/// CFBundleVersion) from the dashboard (/versiones); `min_compat` is kept for
/// older installs. While both are null nothing happens; an install below either
/// minimum is blocked by `ForceUpdateView` until it updates from the App Store.
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
        static let cachedMinBuild = "aliaro.forceUpdate.minBuildIos"
    }
    private let defaults = UserDefaults.standard
    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?

    private init() {
        let cached = UserDefaults.standard.object(forKey: Keys.cachedMin) as? Int
        let cachedBuild = UserDefaults.standard.object(forKey: Keys.cachedMinBuild) as? Int
        required = ForceUpdate.isBelow(cached, minBuild: cachedBuild)
    }

    func start() async {
        await refresh()
        if channel == nil { await listenForChanges() }
    }

    /// Every time the app becomes active: catches a minimum set while it was in the background.
    func refresh() async {
        await reportVersion()
        do {
            let rows: [RemoteAppCompat] = try await supabase
                .from("app_compat")
                .select("min_compat,min_build_ios")
                .execute()
                .value
            let min = rows.first?.minCompat
            let minBuild = rows.first?.minBuild
            if let min { defaults.set(min, forKey: Keys.cachedMin) } else { defaults.removeObject(forKey: Keys.cachedMin) }
            if let minBuild { defaults.set(minBuild, forKey: Keys.cachedMinBuild) } else { defaults.removeObject(forKey: Keys.cachedMinBuild) }
            let isRequired = ForceUpdate.isBelow(min, minBuild: minBuild)
            if isRequired && !required {
                Track.event("force_update_shown", ["min_compat": min, "compat": ALIARO_COMPAT, "min_build": minBuild, "build": APP_BUILD])
            }
            required = isRequired
        } catch {
            print("⚠️ Could not fetch app_compat, keeping cached value (\(error))")
        }
    }

    /// Tells the server which version this member is running (RPC
    /// `report_app_version` → `family_members.app_version/app_build/app_platform/app_seen_at`),
    /// so Varo can see in the dashboard who is still on an old build before raising the minimum.
    /// Only with a session; failures are ignored.
    private func reportVersion() async {
        guard supabase.auth.currentSession != nil else { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        struct Params: Encodable { let p_version: String; let p_platform: String; let p_build: Int }
        do {
            try await supabase
                .rpc("report_app_version", params: Params(p_version: version, p_platform: "ios", p_build: APP_BUILD))
                .execute()
        } catch {
            print("⚠️ Could not report app version (\(error))")
        }
    }

    private static func isBelow(_ min: Int?, minBuild: Int?) -> Bool {
        if let min, ALIARO_COMPAT < min { return true }
        if let minBuild, APP_BUILD < minBuild { return true }
        return false
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
