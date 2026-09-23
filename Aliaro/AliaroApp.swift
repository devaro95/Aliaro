import SwiftUI
import SwiftData

@main
struct AliaroApp: App {
    @UIApplicationDelegateAdaptor(AliaroAppDelegate.self) private var appDelegate
    @StateObject private var familySession = FamilySession.shared
    @StateObject private var familyService = FamilyService(session: FamilySession.shared)
    @StateObject private var authSession = AuthSession.shared
    @StateObject private var dataSync = AppDataSyncCoordinator()
    @StateObject private var premiumManager = PremiumManager.shared

    let modelContainer: ModelContainer = {
        let schema = Schema([
            GroceryItem.self,
            ShoppingList.self,
            ShoppingListEntry.self,
            HouseTask.self,
            HouseTaskLog.self,
            MealPlanEntry.self,
            Dish.self,
            FamilyMember.self,
            Reminder.self,
            FamilyEvent.self,
            Expense.self,
            ExpenseCategory.self,
            ActivityLogEntry.self,
            ExpenseArchive.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // The on-device store doesn't match the current schema (e.g. a
            // model gained/lost a property, like Expense.categoryIDs) and
            // SwiftData can't migrate it automatically. Everything here is
            // just a cache of Supabase, re-synced on the next family fetch,
            // so it's safe to reset the local store instead of crashing.
            print("⚠️ Could not open SwiftData store (\(error)), resetting local cache")
            let storeURL = configuration.url
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Could not create the SwiftData ModelContainer even after resetting the local store: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(familySession)
                .environmentObject(familyService)
                .environmentObject(authSession)
                .environmentObject(dataSync)
                .environmentObject(premiumManager)
                .onAppear {
                    PushNotificationManager.shared.attach(familyService: familyService)
                    // Notification permission is requested right after the
                    // welcome carousel (skip or last page), not here — see
                    // ContentView's AppIntroView.onFinish.
                    // Every device gets a Supabase identity from the first
                    // launch, anonymous until the person chooses to sign
                    // in — see `AuthSession`. Wipe first: a stale Keychain
                    // session from a previous owner must not survive a
                    // fresh install (see AuthSession's privacy note).
                    Task {
                        await authSession.wipeStaleSessionIfFreshInstall()
                        await authSession.ensureSession()
                        // RLS is scoped to family_members.auth_user_id — this
                        // self-heals that column for the case it's stale/null
                        // (see FamilyService.linkAuthIfNeeded doc comment).
                        await familyService.linkAuthIfNeeded()
                    }
                    Task {
                        await premiumManager.start()
                    }
                    Track.refreshUserProperties()
                }
        }
        .modelContainer(modelContainer)
    }
}
