import Foundation
import SwiftData
import Supabase

// MARK: - Remote rows (Supabase) — one per table, flat snake_case shape
// so it matches Postgres's columns exactly.

struct RemoteFamilyMember: FamilySynced {
    static let tableName = "family_members"
    var id: UUID
    var family_id: UUID
    var name: String
    var emoji: String
    var is_creator: Bool
    var joined_at: Date
    var is_admin: Bool = false
    var restricted_permissions: [String] = []
}

struct RemoteDish: FamilySynced {
    static let tableName = "dishes"
    var id: UUID
    var family_id: UUID
    var name: String
    var created_at: Date
}

struct RemoteMealPlanEntry: FamilySynced {
    static let tableName = "meal_plan_entries"
    var id: UUID
    var family_id: UUID
    var weekday: Int
    var meal_type: String
    var dish_id: UUID
    var dish_name: String
    var updated_at: Date
}

struct RemoteGroceryItem: FamilySynced {
    static let tableName = "grocery_items"
    var id: UUID
    var family_id: UUID
    var name: String
    var created_at: Date
}

struct RemoteShoppingList: FamilySynced {
    static let tableName = "shopping_lists"
    var id: UUID
    var family_id: UUID
    var name: String
    var position: Int
    var created_at: Date
}

struct RemoteShoppingListEntry: FamilySynced {
    static let tableName = "shopping_list_entries"
    var id: UUID
    var family_id: UUID
    var item_id: UUID
    var list_id: UUID
    var name: String
    var is_checked: Bool
    var added_at: Date
    var checked_at: Date?
}

struct RemoteHouseTask: FamilySynced {
    static let tableName = "house_tasks"
    var id: UUID
    var family_id: UUID
    var name: String
    var interval_days: Int?
    var created_by: UUID?
    var created_by_name: String?
}

struct RemoteHouseTaskLog: FamilySynced {
    static let tableName = "house_task_logs"
    var id: UUID
    var family_id: UUID
    var task_id: UUID
    var task_name: String
    var completed_at: Date
    var note: String?
    var created_by: UUID?
    var created_by_name: String?
}

struct RemoteFamilyEvent: FamilySynced {
    static let tableName = "family_events"
    var id: UUID
    var family_id: UUID
    var title: String
    var note: String?
    var start_date: Date
    var end_date: Date
    var emoji: String
    var created_at: Date
    var created_by: UUID?
    var created_by_name: String?
}

struct RemoteReminder: FamilySynced {
    static let tableName = "reminders"
    var id: UUID
    var family_id: UUID
    var title: String
    var note: String?
    var fire_date: Date
    var notify_everyone: Bool
    var recipient_ids: [UUID]
    var advance_notice_seconds: [Int]
    var notification_id: String
    var created_at: Date
    /// Which alerts (0 = exact time, or seconds of advance notice) the
    /// server already sent. Only the server writes this; the client sends
    /// it empty on every save so delivery gets rescheduled.
    var notified_offsets: [Int]
    var created_by: UUID?
    var created_by_name: String?
}

struct RemoteCategory: FamilySynced {
    static let tableName = "categories"
    var id: UUID
    var family_id: UUID
    var name: String
    var emoji: String
    var is_default: Bool
    var created_at: Date
}

struct RemoteExpense: FamilySynced {
    static let tableName = "expenses"
    var id: UUID
    var family_id: UUID
    var name: String
    var amount: Double
    var is_income: Bool
    var person_id: UUID
    var person_name: String
    var category_ids: [UUID]
    var occurred_at: Date
    var created_at: Date
}

struct RemoteActivityLogEntry: FamilySynced {
    static let tableName = "activity_log_entries"
    var id: UUID
    var family_id: UUID
    var entity_type: String
    var entity_name: String
    var action: String
    var actor_id: UUID?
    var actor_name: String?
    var created_at: Date
}

struct RemoteExpenseArchive: FamilySynced {
    static let tableName = "expense_archives"
    var id: UUID
    var family_id: UUID
    var name: String
    var start_date: Date
    var end_date: Date
    var archived_by_name: String?
    var snapshot: ExpenseArchiveSnapshot
    var created_at: Date
}

/// Coordinates syncing all of the app's data (menu, shopping, tasks,
/// calendar, reminders) with Supabase: initial load, real time from any
/// device in the group, and uploading local changes.
/// Each screen calls `push·`/`delete·` right after touching SwiftData;
/// `startAll` is called once when entering the tabs.
@MainActor
final class AppDataSyncCoordinator: ObservableObject {
    /// Last sync error (initial fetch), if any. `nil` doesn't mean every
    /// table loaded fine, only that none of them failed.
    @Published var lastError: String?
    /// Set to `true` when the creator removes this device from the
    /// family group (detected in real time on `family_members`). The
    /// root view observes this to clear the local session.
    @Published var wasRemovedFromFamily = false

    private let familyMembers = RemoteSync<RemoteFamilyMember>()
    private let dishes = RemoteSync<RemoteDish>()
    private let mealPlanEntries = RemoteSync<RemoteMealPlanEntry>()
    private let groceryItems = RemoteSync<RemoteGroceryItem>()
    private let shoppingLists = RemoteSync<RemoteShoppingList>()
    private let shoppingListEntries = RemoteSync<RemoteShoppingListEntry>()
    private let houseTasks = RemoteSync<RemoteHouseTask>()
    private let houseTaskLogs = RemoteSync<RemoteHouseTaskLog>()
    private let familyEvents = RemoteSync<RemoteFamilyEvent>()
    private let reminders = RemoteSync<RemoteReminder>()
    private let categories = RemoteSync<RemoteCategory>()
    private let expenses = RemoteSync<RemoteExpense>()
    private let activityLogEntries = RemoteSync<RemoteActivityLogEntry>()
    private let expenseArchives = RemoteSync<RemoteExpenseArchive>()

    private var started = false
    /// Kept so `refreshWidgetSnapshot()` can be called from places (like
    /// `pushReminder`) that don't receive a `modelContext` themselves.
    private var widgetModelContext: ModelContext?

    private func refreshWidgetSnapshot() {
        guard let modelContext = widgetModelContext else { return }
        WidgetSnapshotWriter.refresh(modelContext: modelContext)
    }

    func startAll(familyID: UUID, currentMemberID: UUID, modelContext: ModelContext) async {
        guard !started else { return }
        started = true
        widgetModelContext = modelContext

        // Before fetching anything, we confirm we're still members of the
        // group: if we were removed while the app was closed, there's no
        // real-time event to catch it, so we check here on startup.
        guard await startFamilyMembers(familyID: familyID, currentMemberID: currentMemberID, modelContext: modelContext) else {
            started = false
            wasRemovedFromFamily = true
            return
        }
        await startDishes(familyID: familyID, modelContext: modelContext)
        await startMealPlanEntries(familyID: familyID, modelContext: modelContext)
        await startGroceryItems(familyID: familyID, modelContext: modelContext)
        await startShoppingLists(familyID: familyID, modelContext: modelContext)
        await startShoppingListEntries(familyID: familyID, modelContext: modelContext)
        await startHouseTasks(familyID: familyID, modelContext: modelContext)
        await startHouseTaskLogs(familyID: familyID, modelContext: modelContext)
        await startFamilyEvents(familyID: familyID, modelContext: modelContext)
        await startReminders(familyID: familyID, modelContext: modelContext)
        await startCategories(familyID: familyID, modelContext: modelContext)
        await startExpenses(familyID: familyID, modelContext: modelContext)
        await startActivityLogEntries(familyID: familyID, modelContext: modelContext)
        await startExpenseArchives(familyID: familyID, modelContext: modelContext)
        refreshWidgetSnapshot()
    }

    /// Closes all real-time channels (when leaving the family group).
    func stopAll() async {
        guard started else { return }
        started = false
        await familyMembers.stop()
        await dishes.stop()
        await mealPlanEntries.stop()
        await groceryItems.stop()
        await shoppingLists.stop()
        await shoppingListEntries.stop()
        await houseTasks.stop()
        await houseTaskLogs.stop()
        await familyEvents.stop()
        await reminders.stop()
        await categories.stop()
        await expenses.stop()
        await activityLogEntries.stop()
        await expenseArchives.stop()
    }

    // MARK: FamilyMembers

    /// Fetches the member list and starts its real-time channel. Returns
    /// `false` if, after the fetch, our own `currentMemberID` no longer
    /// appears in the group (we were removed at some point while the app
    /// wasn't listening) — in that case we don't subscribe or sync the
    /// rest of the tables.
    @discardableResult
    private func startFamilyMembers(familyID: UUID, currentMemberID: UUID, modelContext: ModelContext) async -> Bool {
        var stillMember = true
        do {
            let remote = try await familyMembers.fetchAll(familyID: familyID)
            stillMember = remote.contains { $0.id == currentMemberID }
            let remoteIDs = Set(remote.map(\.id))
            for r in remote { applyFamilyMember(r, currentMemberID: currentMemberID, modelContext: modelContext) }
            // Purges local members that no longer exist in the remote
            // group: leftovers from a previous family that was never
            // properly left (e.g. deleted by hand in Supabase, or the
            // device was reinstalled without going through "leave group").
            if let localMembers = try? modelContext.fetch(FetchDescriptor<FamilyMember>()) {
                for local in localMembers where !remoteIDs.contains(local.id) {
                    modelContext.delete(local)
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
        guard stillMember else { return false }

        await familyMembers.start(
            familyID: familyID,
            onUpsert: { [weak self] r in self?.applyFamilyMember(r, currentMemberID: currentMemberID, modelContext: modelContext) },
            onDelete: { [weak self] id in
                let descriptor = FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.id == id })
                if let existing = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(existing)
                }
                // If the deleted member is us, the creator has removed
                // us from the group (or we've left from another
                // device): the local session needs to be cleared.
                if id == currentMemberID {
                    self?.wasRemovedFromFamily = true
                }
            }
        )
        return true
    }

    private func applyFamilyMember(_ remote: RemoteFamilyMember, currentMemberID: UUID, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<FamilyMember>(predicate: #Predicate { $0.id == remote.id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = remote.name
            existing.emoji = remote.emoji
            existing.isCreator = remote.is_creator
            existing.isCurrentDevice = remote.id == currentMemberID
            existing.isAdmin = remote.is_admin
            existing.restrictedPermissions = remote.restricted_permissions
        } else {
            modelContext.insert(FamilyMember(
                id: remote.id, name: remote.name, emoji: remote.emoji,
                createdAt: remote.joined_at, isCurrentDevice: remote.id == currentMemberID,
                isCreator: remote.is_creator, isAdmin: remote.is_admin,
                restrictedPermissions: remote.restricted_permissions
            ))
        }
    }

    // MARK: Dishes

    private func startDishes(familyID: UUID, modelContext: ModelContext) async {
        do {
            let remote = try await dishes.fetchAll(familyID: familyID)
            for r in remote { applyDish(r, modelContext: modelContext) }
        } catch {
            lastError = error.localizedDescription
        }
        await dishes.start(
            familyID: familyID,
            onUpsert: { [weak self] r in self?.applyDish(r, modelContext: modelContext) },
            onDelete: { id in
                let descriptor = FetchDescriptor<Dish>(predicate: #Predicate { $0.id == id })
                if let existing = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(existing)
                }
            }
        )
    }

    private func applyDish(_ remote: RemoteDish, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Dish>(predicate: #Predicate { $0.id == remote.id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = remote.name
        } else {
            modelContext.insert(Dish(id: remote.id, name: remote.name, createdAt: remote.created_at))
        }
    }

    func pushDish(_ dish: Dish, familyID: UUID) {
        let record = RemoteDish(id: dish.id, family_id: familyID, name: dish.name, created_at: dish.createdAt)
        Task { try? await dishes.push(record) }
    }

    func deleteDish(id: UUID) {
        Task { try? await dishes.remove(id: id) }
    }

    // MARK: MealPlanEntries

    private func startMealPlanEntries(familyID: UUID, modelContext: ModelContext) async {
        do {
            let remote = try await mealPlanEntries.fetchAll(familyID: familyID)
            for r in remote { applyMealPlanEntry(r, modelContext: modelContext) }
        } catch {
            lastError = error.localizedDescription
        }
        await mealPlanEntries.start(
            familyID: familyID,
            onUpsert: { [weak self] r in self?.applyMealPlanEntry(r, modelContext: modelContext) },
            onDelete: { [weak self] id in
                let descriptor = FetchDescriptor<MealPlanEntry>(predicate: #Predicate { $0.id == id })
                if let existing = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(existing)
                }
                self?.refreshWidgetSnapshot()
            }
        )
    }

    private func applyMealPlanEntry(_ remote: RemoteMealPlanEntry, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<MealPlanEntry>(predicate: #Predicate { $0.id == remote.id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.weekday = remote.weekday
            existing.mealType = remote.meal_type
            existing.dishID = remote.dish_id
            existing.dishName = remote.dish_name
            existing.updatedAt = remote.updated_at
        } else {
            modelContext.insert(MealPlanEntry(
                id: remote.id,
                weekday: remote.weekday,
                mealType: remote.meal_type,
                dishID: remote.dish_id,
                dishName: remote.dish_name,
                updatedAt: remote.updated_at
            ))
        }
        refreshWidgetSnapshot()
    }

    func pushMealPlanEntry(_ entry: MealPlanEntry, familyID: UUID) {
        let record = RemoteMealPlanEntry(
            id: entry.id, family_id: familyID, weekday: entry.weekday, meal_type: entry.mealType,
            dish_id: entry.dishID, dish_name: entry.dishName, updated_at: entry.updatedAt
        )
        Task { try? await mealPlanEntries.push(record) }
        refreshWidgetSnapshot()
    }

    func deleteMealPlanEntry(id: UUID) {
        Task { try? await mealPlanEntries.remove(id: id) }
        refreshWidgetSnapshot()
    }

    // MARK: GroceryItems

    private func startGroceryItems(familyID: UUID, modelContext: ModelContext) async {
        do {
            let remote = try await groceryItems.fetchAll(familyID: familyID)
            for r in remote { applyGroceryItem(r, modelContext: modelContext) }
        } catch {
            lastError = error.localizedDescription
        }
        await groceryItems.start(
            familyID: familyID,
            onUpsert: { [weak self] r in self?.applyGroceryItem(r, modelContext: modelContext) },
            onDelete: { id in
                let descriptor = FetchDescriptor<GroceryItem>(predicate: #Predicate { $0.id == id })
                if let existing = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(existing)
                }
            }
        )
    }

    private func applyGroceryItem(_ remote: RemoteGroceryItem, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<GroceryItem>(predicate: #Predicate { $0.id == remote.id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = remote.name
        } else {
            modelContext.insert(GroceryItem(id: remote.id, name: remote.name, createdAt: remote.created_at))
        }
    }

    func pushGroceryItem(_ item: GroceryItem, familyID: UUID) {
        let record = RemoteGroceryItem(id: item.id, family_id: familyID, name: item.name, created_at: item.createdAt)
        Task { try? await groceryItems.push(record) }
    }

    func deleteGroceryItem(id: UUID) {
        Task { try? await groceryItems.remove(id: id) }
    }

    // MARK: ShoppingLists

    private func startShoppingLists(familyID: UUID, modelContext: ModelContext) async {
        do {
            let remote = try await shoppingLists.fetchAll(familyID: familyID)
            for r in remote { applyShoppingList(r, modelContext: modelContext) }
        } catch {
            lastError = error.localizedDescription
        }
        await shoppingLists.start(
            familyID: familyID,
            onUpsert: { [weak self] r in self?.applyShoppingList(r, modelContext: modelContext) },
            onDelete: { id in
                let descriptor = FetchDescriptor<ShoppingList>(predicate: #Predicate { $0.id == id })
                if let existing = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(existing)
                }
            }
        )
    }

    private func applyShoppingList(_ remote: RemoteShoppingList, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<ShoppingList>(predicate: #Predicate { $0.id == remote.id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = remote.name
            existing.position = remote.position
        } else {
            modelContext.insert(ShoppingList(id: remote.id, name: remote.name, position: remote.position, createdAt: remote.created_at))
        }
    }

    func pushShoppingList(_ list: ShoppingList, familyID: UUID) {
        let record = RemoteShoppingList(id: list.id, family_id: familyID, name: list.name, position: list.position, created_at: list.createdAt)
        Task { try? await shoppingLists.push(record) }
    }

    func deleteShoppingList(id: UUID) {
        Task { try? await shoppingLists.remove(id: id) }
    }

    // MARK: ShoppingListEntries

    private func startShoppingListEntries(familyID: UUID, modelContext: ModelContext) async {
        do {
            let remote = try await shoppingListEntries.fetchAll(familyID: familyID)
            for r in remote { applyShoppingListEntry(r, modelContext: modelContext) }
        } catch {
            lastError = error.localizedDescription
        }
        await shoppingListEntries.start(
            familyID: familyID,
            onUpsert: { [weak self] r in self?.applyShoppingListEntry(r, modelContext: modelContext) },
            onDelete: { id in
                let descriptor = FetchDescriptor<ShoppingListEntry>(predicate: #Predicate { $0.id == id })
                if let existing = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(existing)
                }
            }
        )
    }

    private func applyShoppingListEntry(_ remote: RemoteShoppingListEntry, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<ShoppingListEntry>(predicate: #Predicate { $0.id == remote.id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.itemID = remote.item_id
            existing.listID = remote.list_id
            existing.name = remote.name
            existing.isChecked = remote.is_checked
            existing.addedAt = remote.added_at
            existing.checkedAt = remote.checked_at
        } else {
            modelContext.insert(ShoppingListEntry(
                id: remote.id, itemID: remote.item_id, listID: remote.list_id, name: remote.name,
                isChecked: remote.is_checked, addedAt: remote.added_at, checkedAt: remote.checked_at
            ))
        }
    }

    func pushShoppingListEntry(_ entry: ShoppingListEntry, familyID: UUID) {
        let record = RemoteShoppingListEntry(
            id: entry.id, family_id: familyID, item_id: entry.itemID, list_id: entry.listID, name: entry.name,
            is_checked: entry.isChecked, added_at: entry.addedAt, checked_at: entry.checkedAt
        )
        Task { try? await shoppingListEntries.push(record) }
    }

    func deleteShoppingListEntry(id: UUID) {
        Task { try? await shoppingListEntries.remove(id: id) }
    }

    // MARK: HouseTasks

    private func startHouseTasks(familyID: UUID, modelContext: ModelContext) async {
        do {
            let remote = try await houseTasks.fetchAll(familyID: familyID)
            for r in remote { applyHouseTask(r, modelContext: modelContext) }
        } catch {
            lastError = error.localizedDescription
        }
        await houseTasks.start(
            familyID: familyID,
            onUpsert: { [weak self] r in self?.applyHouseTask(r, modelContext: modelContext) },
            onDelete: { id in
                let descriptor = FetchDescriptor<HouseTask>(predicate: #Predicate { $0.id == id })
                if let existing = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(existing)
                }
            }
        )
    }

    private func applyHouseTask(_ remote: RemoteHouseTask, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<HouseTask>(predicate: #Predicate { $0.id == remote.id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = remote.name
            existing.intervalDays = remote.interval_days
            existing.createdByID = remote.created_by
            existing.createdByName = remote.created_by_name
        } else {
            modelContext.insert(HouseTask(
                id: remote.id, name: remote.name, intervalDays: remote.interval_days,
                createdByID: remote.created_by, createdByName: remote.created_by_name
            ))
        }
    }

    func pushHouseTask(_ task: HouseTask, familyID: UUID) {
        let record = RemoteHouseTask(
            id: task.id, family_id: familyID, name: task.name, interval_days: task.intervalDays,
            created_by: task.createdByID, created_by_name: task.createdByName
        )
        Task { try? await houseTasks.push(record) }
    }

    func deleteHouseTask(id: UUID) {
        Task { try? await houseTasks.remove(id: id) }
    }

    // MARK: HouseTaskLogs

    private func startHouseTaskLogs(familyID: UUID, modelContext: ModelContext) async {
        do {
            let remote = try await houseTaskLogs.fetchAll(familyID: familyID)
            for r in remote { applyHouseTaskLog(r, modelContext: modelContext) }
        } catch {
            lastError = error.localizedDescription
        }
        await houseTaskLogs.start(
            familyID: familyID,
            onUpsert: { [weak self] r in self?.applyHouseTaskLog(r, modelContext: modelContext) },
            onDelete: { id in
                let descriptor = FetchDescriptor<HouseTaskLog>(predicate: #Predicate { $0.id == id })
                if let existing = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(existing)
                }
            }
        )
    }

    private func applyHouseTaskLog(_ remote: RemoteHouseTaskLog, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<HouseTaskLog>(predicate: #Predicate { $0.id == remote.id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.taskID = remote.task_id
            existing.taskName = remote.task_name
            existing.completedAt = remote.completed_at
            existing.note = remote.note
            existing.createdByID = remote.created_by
            existing.createdByName = remote.created_by_name
        } else {
            modelContext.insert(HouseTaskLog(
                id: remote.id, taskID: remote.task_id, taskName: remote.task_name,
                completedAt: remote.completed_at, note: remote.note,
                createdByID: remote.created_by, createdByName: remote.created_by_name
            ))
        }
    }

    func pushHouseTaskLog(_ log: HouseTaskLog, familyID: UUID) {
        let record = RemoteHouseTaskLog(
            id: log.id, family_id: familyID, task_id: log.taskID, task_name: log.taskName,
            completed_at: log.completedAt, note: log.note,
            created_by: log.createdByID, created_by_name: log.createdByName
        )
        Task { try? await houseTaskLogs.push(record) }
    }

    func deleteHouseTaskLog(id: UUID) {
        Task { try? await houseTaskLogs.remove(id: id) }
    }

    // MARK: FamilyEvents

    private func startFamilyEvents(familyID: UUID, modelContext: ModelContext) async {
        do {
            let remote = try await familyEvents.fetchAll(familyID: familyID)
            for r in remote { applyFamilyEvent(r, modelContext: modelContext) }
        } catch {
            lastError = error.localizedDescription
        }
        await familyEvents.start(
            familyID: familyID,
            onUpsert: { [weak self] r in self?.applyFamilyEvent(r, modelContext: modelContext) },
            onDelete: { [weak self] id in
                let descriptor = FetchDescriptor<FamilyEvent>(predicate: #Predicate { $0.id == id })
                if let existing = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(existing)
                }
                self?.refreshWidgetSnapshot()
            }
        )
    }

    private func applyFamilyEvent(_ remote: RemoteFamilyEvent, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<FamilyEvent>(predicate: #Predicate { $0.id == remote.id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.title = remote.title
            existing.note = remote.note
            existing.startDate = remote.start_date
            existing.endDate = remote.end_date
            existing.emoji = remote.emoji
            existing.createdByID = remote.created_by
            existing.createdByName = remote.created_by_name
        } else {
            modelContext.insert(FamilyEvent(
                id: remote.id, title: remote.title, note: remote.note,
                startDate: remote.start_date, endDate: remote.end_date,
                emoji: remote.emoji, createdAt: remote.created_at,
                createdByID: remote.created_by, createdByName: remote.created_by_name
            ))
        }
        refreshWidgetSnapshot()
    }

    func pushFamilyEvent(_ event: FamilyEvent, familyID: UUID) {
        let record = RemoteFamilyEvent(
            id: event.id, family_id: familyID, title: event.title, note: event.note,
            start_date: event.startDate, end_date: event.endDate, emoji: event.emoji, created_at: event.createdAt,
            created_by: event.createdByID, created_by_name: event.createdByName
        )
        Task { try? await familyEvents.push(record) }
        refreshWidgetSnapshot()
    }

    func deleteFamilyEvent(id: UUID) {
        Task { try? await familyEvents.remove(id: id) }
        refreshWidgetSnapshot()
    }

    // MARK: Reminders

    private func startReminders(familyID: UUID, modelContext: ModelContext) async {
        do {
            let remote = try await reminders.fetchAll(familyID: familyID)
            for r in remote { applyReminder(r, modelContext: modelContext) }
        } catch {
            lastError = error.localizedDescription
        }
        await reminders.start(
            familyID: familyID,
            onUpsert: { [weak self] r in self?.applyReminder(r, modelContext: modelContext) },
            onDelete: { [weak self] id in
                let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == id })
                if let existing = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(existing)
                }
                self?.refreshWidgetSnapshot()
            }
        )
    }

    private func applyReminder(_ remote: RemoteReminder, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == remote.id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.title = remote.title
            existing.note = remote.note
            existing.fireDate = remote.fire_date
            existing.notifyEveryone = remote.notify_everyone
            existing.recipientIDs = remote.recipient_ids
            existing.advanceNoticeSeconds = remote.advance_notice_seconds
            existing.notificationID = remote.notification_id
            existing.createdByID = remote.created_by
            existing.createdByName = remote.created_by_name
        } else {
            modelContext.insert(Reminder(
                id: remote.id, title: remote.title, note: remote.note, fireDate: remote.fire_date,
                notifyEveryone: remote.notify_everyone, recipientIDs: remote.recipient_ids,
                advanceNoticeSeconds: remote.advance_notice_seconds,
                notificationID: remote.notification_id, createdAt: remote.created_at,
                createdByID: remote.created_by, createdByName: remote.created_by_name
            ))
        }
        refreshWidgetSnapshot()
    }

    func pushReminder(_ reminder: Reminder, familyID: UUID) {
        let record = RemoteReminder(
            id: reminder.id, family_id: familyID, title: reminder.title, note: reminder.note,
            fire_date: reminder.fireDate, notify_everyone: reminder.notifyEveryone,
            recipient_ids: reminder.recipientIDs, advance_notice_seconds: reminder.advanceNoticeSeconds,
            notification_id: reminder.notificationID, created_at: reminder.createdAt,
            // Reset on every save: an edited reminder (e.g. the time is
            // changed) should notify again even if it had already notified before.
            notified_offsets: [],
            created_by: reminder.createdByID, created_by_name: reminder.createdByName
        )
        Task { try? await reminders.push(record) }
        refreshWidgetSnapshot()
    }

    func deleteReminder(id: UUID) {
        Task { try? await reminders.remove(id: id) }
        refreshWidgetSnapshot()
    }

    // MARK: Categories

    private func startCategories(familyID: UUID, modelContext: ModelContext) async {
        do {
            let remote = try await categories.fetchAll(familyID: familyID)
            for r in remote { applyCategory(r, modelContext: modelContext) }
        } catch {
            lastError = error.localizedDescription
        }
        await categories.start(
            familyID: familyID,
            onUpsert: { [weak self] r in self?.applyCategory(r, modelContext: modelContext) },
            onDelete: { id in
                let descriptor = FetchDescriptor<ExpenseCategory>(predicate: #Predicate { $0.id == id })
                if let existing = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(existing)
                }
            }
        )
    }

    private func applyCategory(_ remote: RemoteCategory, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<ExpenseCategory>(predicate: #Predicate { $0.id == remote.id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = remote.name
            existing.emoji = remote.emoji
            existing.isDefault = remote.is_default
        } else {
            modelContext.insert(ExpenseCategory(
                id: remote.id, name: remote.name, emoji: remote.emoji,
                isDefault: remote.is_default, createdAt: remote.created_at
            ))
        }
    }

    func pushCategory(_ category: ExpenseCategory, familyID: UUID) {
        let record = RemoteCategory(
            id: category.id, family_id: familyID, name: category.name, emoji: category.emoji,
            is_default: category.isDefault, created_at: category.createdAt
        )
        Task { try? await categories.push(record) }
    }

    func deleteCategory(id: UUID) {
        Task { try? await categories.remove(id: id) }
    }

    // MARK: Expenses

    private func startExpenses(familyID: UUID, modelContext: ModelContext) async {
        do {
            let remote = try await expenses.fetchAll(familyID: familyID)
            for r in remote { applyExpense(r, modelContext: modelContext) }
        } catch {
            lastError = error.localizedDescription
        }
        await expenses.start(
            familyID: familyID,
            onUpsert: { [weak self] r in self?.applyExpense(r, modelContext: modelContext) },
            onDelete: { id in
                let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })
                if let existing = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(existing)
                    try? modelContext.save()
                }
            }
        )
    }

    private func applyExpense(_ remote: RemoteExpense, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.id == remote.id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = remote.name
            existing.amount = remote.amount
            existing.isIncome = remote.is_income
            existing.personID = remote.person_id
            existing.personName = remote.person_name
            existing.categoryIDs = remote.category_ids
            existing.occurredAt = remote.occurred_at
        } else {
            modelContext.insert(Expense(
                id: remote.id, name: remote.name, amount: remote.amount, isIncome: remote.is_income,
                personID: remote.person_id, personName: remote.person_name,
                categoryIDs: remote.category_ids,
                occurredAt: remote.occurred_at, createdAt: remote.created_at
            ))
        }
    }

    func pushExpense(_ expense: Expense, familyID: UUID) {
        let record = RemoteExpense(
            id: expense.id, family_id: familyID, name: expense.name, amount: expense.amount,
            is_income: expense.isIncome, person_id: expense.personID, person_name: expense.personName,
            category_ids: expense.categoryIDs,
            occurred_at: expense.occurredAt, created_at: expense.createdAt
        )
        Task { try? await expenses.push(record) }
    }

    func deleteExpense(id: UUID) {
        Task { try? await expenses.remove(id: id) }
    }

    // MARK: ExpenseArchives (archived finances)

    private func startExpenseArchives(familyID: UUID, modelContext: ModelContext) async {
        do {
            let remote = try await expenseArchives.fetchAll(familyID: familyID)
            for r in remote { applyExpenseArchive(r, modelContext: modelContext) }
        } catch {
            lastError = error.localizedDescription
        }
        await expenseArchives.start(
            familyID: familyID,
            onUpsert: { [weak self] r in self?.applyExpenseArchive(r, modelContext: modelContext) },
            onDelete: { id in
                let descriptor = FetchDescriptor<ExpenseArchive>(predicate: #Predicate { $0.id == id })
                if let existing = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(existing)
                }
            }
        )
    }

    private func applyExpenseArchive(_ remote: RemoteExpenseArchive, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<ExpenseArchive>(predicate: #Predicate { $0.id == remote.id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = remote.name
            existing.startDate = remote.start_date
            existing.endDate = remote.end_date
            existing.archivedByName = remote.archived_by_name
            existing.snapshotData = (try? JSONEncoder().encode(remote.snapshot)) ?? existing.snapshotData
        } else {
            modelContext.insert(ExpenseArchive(
                id: remote.id, name: remote.name, startDate: remote.start_date, endDate: remote.end_date,
                archivedByName: remote.archived_by_name, snapshot: remote.snapshot, createdAt: remote.created_at
            ))
        }
    }

    /// Uploads the archive and, only once it's safely stored, deletes the
    /// archived transactions from the live list (other devices drop them
    /// through the `expenses` real-time channel). Throws so the UI can keep
    /// everything as it was if either step fails.
    func archiveExpenses(_ archive: ExpenseArchive, expenseIDs: [UUID], familyID: UUID) async throws {
        let record = RemoteExpenseArchive(
            id: archive.id, family_id: familyID, name: archive.name,
            start_date: archive.startDate, end_date: archive.endDate,
            archived_by_name: archive.archivedByName, snapshot: archive.snapshot,
            created_at: archive.createdAt
        )
        try await expenseArchives.push(record)
        guard !expenseIDs.isEmpty else { return }
        try await supabase
            .from(RemoteExpense.tableName)
            .delete()
            .eq("family_id", value: familyID)
            .in("id", values: expenseIDs.map(\.uuidString))
            .execute()
    }

    func deleteExpenseArchive(id: UUID) {
        Task { try? await expenseArchives.remove(id: id) }
    }

    // MARK: ActivityLogEntries ("History")

    private func startActivityLogEntries(familyID: UUID, modelContext: ModelContext) async {
        do {
            let remote = try await activityLogEntries.fetchAll(familyID: familyID)
            for r in remote { applyActivityLogEntry(r, modelContext: modelContext) }
        } catch {
            lastError = error.localizedDescription
        }
        await activityLogEntries.start(
            familyID: familyID,
            onUpsert: { [weak self] r in self?.applyActivityLogEntry(r, modelContext: modelContext) },
            onDelete: { id in
                let descriptor = FetchDescriptor<ActivityLogEntry>(predicate: #Predicate { $0.id == id })
                if let existing = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(existing)
                }
            }
        )
    }

    private func applyActivityLogEntry(_ remote: RemoteActivityLogEntry, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<ActivityLogEntry>(predicate: #Predicate { $0.id == remote.id })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.entityType = remote.entity_type
            existing.entityName = remote.entity_name
            existing.action = remote.action
            existing.actorID = remote.actor_id
            existing.actorName = remote.actor_name
        } else {
            modelContext.insert(ActivityLogEntry(
                id: remote.id, entityType: remote.entity_type, entityName: remote.entity_name,
                action: remote.action, actorID: remote.actor_id, actorName: remote.actor_name,
                createdAt: remote.created_at
            ))
        }
    }

    /// Records a create/update/delete on a shared item for the group's
    /// "History": who did what, and when. Call right after the
    /// corresponding `push·`/`delete·`. Weekly menu and shopping lists
    /// are excluded on purpose, same as the app's rule against showing
    /// authorship for those.
    func logActivity(
        entityType: String,
        entityName: String,
        action: String,
        actorID: UUID?,
        actorName: String?,
        familyID: UUID,
        modelContext: ModelContext
    ) {
        let entry = ActivityLogEntry(
            entityType: entityType, entityName: entityName, action: action,
            actorID: actorID, actorName: actorName
        )
        modelContext.insert(entry)
        try? modelContext.save()
        let record = RemoteActivityLogEntry(
            id: entry.id, family_id: familyID, entity_type: entityType, entity_name: entityName,
            action: action, actor_id: actorID, actor_name: actorName, created_at: entry.createdAt
        )
        Task { try? await activityLogEntries.push(record) }
    }
}
