import Foundation
import Supabase

/// One row of the `premium_features` Supabase table: whether a given
/// `PremiumFeature.rawValue` currently requires a subscription. Global —
/// not tied to a family group, it's the same for every install.
private struct RemotePremiumFeature: Codable {
    let key: String
    let isPremium: Bool

    enum CodingKeys: String, CodingKey {
        case key
        case isPremium = "is_premium"
    }
}

/// Live mirror of which features are currently paywalled. Fetched once at
/// launch and kept in sync via Realtime, so Varo can turn a feature free
/// or premium from Supabase (SQL update on `premium_features`) and every
/// device picks it up immediately — no app update, no app restart.
@MainActor
final class PremiumConfig: ObservableObject {
    static let shared = PremiumConfig()

    /// `PremiumFeature.rawValue` → currently premium. A key missing here
    /// is treated as free (fails open — e.g. before the first successful
    /// fetch, or for a table row with no matching `PremiumFeature` case).
    @Published private(set) var premiumKeys: Set<String>

    private enum Keys {
        static let cached = "aliaro.premiumFeatureCache"
    }
    private let defaults = UserDefaults.standard
    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?

    /// Used only until the first successful fetch (first launch, or
    /// offline): everything ships premium out of the box, same as the
    /// rows seeded in Supabase.
    private static let initialDefaults = Set(PremiumFeature.allCases.map(\.rawValue))

    private init() {
        if let cached = defaults.stringArray(forKey: Keys.cached) {
            premiumKeys = Set(cached)
        } else {
            premiumKeys = PremiumConfig.initialDefaults
        }
    }

    func isPremium(_ feature: PremiumFeature) -> Bool {
        premiumKeys.contains(feature.rawValue)
    }

    func start() async {
        await refresh()
        await listenForChanges()
    }

    private func refresh() async {
        do {
            let rows: [RemotePremiumFeature] = try await supabase
                .from("premium_features")
                .select()
                .execute()
                .value
            apply(rows)
        } catch {
            print("⚠️ Could not fetch premium_features, keeping cached/default config (\(error))")
        }
    }

    private func apply(_ rows: [RemotePremiumFeature]) {
        premiumKeys = Set(rows.filter(\.isPremium).map(\.key))
        defaults.set(Array(premiumKeys), forKey: Keys.cached)
    }

    /// Any change to the table (Varo toggling a feature) re-fetches the
    /// whole (tiny) table rather than decoding the incremental payload —
    /// simpler, and cheap enough for a handful of rows.
    private func listenForChanges() async {
        let newChannel = supabase.channel("sync-premium-features")
        let inserts = newChannel.postgresChange(InsertAction.self, schema: "public", table: "premium_features")
        let updates = newChannel.postgresChange(UpdateAction.self, schema: "public", table: "premium_features")
        let deletes = newChannel.postgresChange(DeleteAction.self, schema: "public", table: "premium_features")
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
