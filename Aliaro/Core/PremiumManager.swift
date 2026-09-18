import Foundation
import Combine
import Supabase

/// Single source of truth views ask to know whether something needs a
/// subscription: combines the live "which features are premium right
/// now" config with whether Aliaro Premium is active — either on this
/// device (StoreKit), or for the family group as a whole (any member's
/// device having subscribed marks the shared `families.is_premium`, so
/// premium features unlock for everyone in the group, not just the payer).
@MainActor
final class PremiumManager: ObservableObject {
    static let shared = PremiumManager()

    let config = PremiumConfig.shared
    let subscriptions = SubscriptionManager.shared

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        // Re-publish so a view observing only `PremiumManager` still
        // updates when the remote config, the subscription status, or the
        // family's own premium flag change.
        config.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        subscriptions.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        FamilySession.shared.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Whenever this device's entitlement is (re)checked — start,
        // purchase, restore, renewal — push the latest status up to the
        // family group this device belongs to, if any.
        subscriptions.onEntitlementChanged = { [weak self] in
            self?.syncFamilyPremiumStatus()
        }
    }

    func start() async {
        async let configTask: () = config.start()
        async let subscriptionsTask: () = subscriptions.start()
        _ = await (configTask, subscriptionsTask)
    }

    /// Whether the user needs to subscribe to use this feature right now:
    /// premium in remote config, AND neither this device nor the family
    /// group it belongs to has an active subscription.
    func isLocked(_ feature: PremiumFeature) -> Bool {
        guard config.isPremium(feature) else { return false }
        if subscriptions.isSubscribed { return false }
        if FamilySession.shared.isFamilyPremium { return false }
        return true
    }

    /// Tells the backend whether this device's Aliaro Premium entitlement
    /// is currently active, so the family group it belongs to (if any) is
    /// flagged accordingly — every device in the group then sees premium
    /// unlocked, and `join-family` can enforce the free member cap
    /// server-side (a shared invite code can't grow the group past it for
    /// free). No-ops if this device hasn't joined a family group yet.
    ///
    /// Trust model: same as the rest of the app (no server-side App Store
    /// receipt verification) — this device's StoreKit entitlement is
    /// trusted client-side, consistent with how permissions/admin flags
    /// already work here.
    func syncFamilyPremiumStatus() {
        guard let familyID = FamilySession.shared.familyID, let memberID = FamilySession.shared.memberID else { return }
        let isPremiumNow = subscriptions.isSubscribed
        Task {
            struct Body: Encodable { let familyId: UUID; let memberId: UUID; let isPremium: Bool }
            struct SyncResponse: Decodable { let ok: Bool; let isPremium: Bool }
            do {
                let response: SyncResponse = try await invokeEdgeFunction(
                    "update-family-premium-status",
                    options: FunctionInvokeOptions(body: Body(familyId: familyID, memberId: memberID, isPremium: isPremiumNow))
                )
                FamilySession.shared.setFamilyPremium(response.isPremium)
            } catch {
                print("⚠️ Could not sync family premium status (\(error))")
            }
        }
    }
}
