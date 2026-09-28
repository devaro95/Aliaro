import SwiftUI

/// One-time welcome carousel shown the very first time the app runs on a
/// device, before `FamilyOnboardingView` (create/join group). Purely
/// informational — introduces what Aliaro does — and is never shown again
/// once dismissed (tracked by `FamilySession.hasSeenAppIntro`), including
/// after leaving a family group later on.
///
/// Each page shows a small mockup of the real app (same idea as the Board
/// premium banner) instead of a lone icon, so the features read at a glance.
struct AppIntroView: View {
    let onFinish: () -> Void

    @State private var page = 0

    private let pages: [IntroPage] = [
        IntroPage(
            kind: .welcome,
            title: "Welcome to Aliaro",
            subtitle: "Organize your home life as a family, all in one shared space.",
            accent: ALIColors.peopleAccent
        ),
        IntroPage(
            kind: .shopping,
            title: "Shared shopping list",
            subtitle: "Everyone adds and checks off items, updated in real time for the whole family.",
            accent: ALIColors.shoppingAccent
        ),
        IntroPage(
            kind: .tasks,
            title: "House tasks",
            subtitle: "Split the chores and see at a glance what's done, what's next and what's overdue.",
            accent: ALIColors.houseTasksAccent
        ),
        IntroPage(
            kind: .menu,
            title: "Weekly menu",
            subtitle: "Plan lunches and dinners for the week and stop wondering what's for dinner.",
            accent: ALIColors.weeklyMenuAccent
        ),
        IntroPage(
            kind: .calendar,
            title: "Calendar & reminders",
            subtitle: "A shared family calendar and reminders, so nobody misses a thing.",
            accent: ALIColors.familyAccent
        ),
        IntroPage(
            kind: .economy,
            title: "Economy & history",
            subtitle: "Track shared expenses by category, and see who did what with a full activity history.",
            accent: ALIColors.economiaAccent
        )
    ]

    private var isLastPage: Bool { page == pages.count - 1 }

    var body: some View {
        trackedBody.trackScreen("onboarding_intro")
    }

    @ViewBuilder
    private var trackedBody: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                ALITextButton(text: "Skip") {
                    Track.event("intro_skip", ["page": page, "pages": pages.count])
                    onFinish()
                }
                    .frame(width: 80)
            }
            .padding(.top, 12)
            .padding(.trailing, 12)
            .opacity(isLastPage ? 0 : 1)

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, introPage in
                    IntroPageView(page: introPage, isActive: index == page, showWordmark: index == 0)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: page) { _, p in Track.event("intro_page_view", ["page": p]) }

            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? pages[index].accent : ALIColors.outline)
                        .frame(width: index == page ? 22 : 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: page)
                }
            }
            .padding(.bottom, 24)

            VStack(spacing: 12) {
                if isLastPage {
                    ALIPrimaryButton(text: "Get started", accent: pages[page].accent) {
                        Track.event("intro_complete", ["pages": pages.count])
                        onFinish()
                    }
                } else {
                    ALIPrimaryButton(text: "Next", accent: pages[page].accent) {
                        withAnimation { page += 1 }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALIColors.background)
    }
}

private struct IntroPage {
    enum Kind { case welcome, shopping, tasks, menu, calendar, economy }

    let kind: Kind
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let accent: Color
}

private struct IntroPageView: View {
    let page: IntroPage
    let isActive: Bool
    var showWordmark: Bool = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 8)

            ZStack {
                // Soft accent glow behind the mockup.
                Circle()
                    .fill(page.accent.opacity(0.28))
                    .frame(width: 280, height: 280)
                    .blur(radius: 30)

                mockup
            }
            .frame(height: 320)
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                if showWordmark {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Welcome to")
                            .font(ALITypography.headlineLarge)
                            .foregroundStyle(ALIColors.ink)
                        AliaroWordmark(size: 26)
                    }
                } else {
                    Text(page.title)
                        .font(ALITypography.headlineLarge)
                        .foregroundStyle(ALIColors.ink)
                        .multilineTextAlignment(.center)
                }
                Text(page.subtitle)
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    private var mockup: some View {
        switch page.kind {
        case .welcome: WelcomeMockup(isActive: isActive)
        case .shopping: ShoppingMockup(isActive: isActive)
        case .tasks: TasksMockup(isActive: isActive)
        case .menu: MenuMockup(isActive: isActive)
        case .calendar: CalendarMockup(isActive: isActive)
        case .economy: EconomyMockup(isActive: isActive)
        }
    }
}

// MARK: - Mockup building blocks

/// Small phone frame with a top bar (accent dot + screen title + avatar).
private struct MockPhone<Content: View>: View {
    let title: LocalizedStringKey
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                MockAvatar(initial: "M", color: ALIColors.peopleAccent, size: 18)
            }
            content
        }
        .padding(12)
        .frame(width: 196, alignment: .top)
        .background(ALIColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(ALIColors.ink.opacity(0.15), lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
    }
}

/// Floating card that pops over the phone, slightly rotated.
private struct MockFloatingCard<Content: View>: View {
    let color: Color
    var rotation: Double = 0
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(9)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .rotationEffect(.degrees(rotation))
            .shadow(color: color.opacity(0.55), radius: 8, y: 3)
    }
}

private struct MockAvatar: View {
    let initial: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Text(verbatim: initial)
                    .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                    .foregroundStyle(ALIColors.onAccent)
            )
            .overlay(Circle().stroke(ALIColors.background, lineWidth: 1.5))
    }
}

/// Pops floating elements in when the page becomes visible.
private struct PopIn: ViewModifier {
    let isActive: Bool
    var delay: Double = 0.15
    var from: CGSize = CGSize(width: 0, height: 12)

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? 1 : 0.85)
            .offset(isActive ? .zero : from)
            .opacity(isActive ? 1 : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.7).delay(isActive ? delay : 0), value: isActive)
    }
}

private extension View {
    func popIn(_ isActive: Bool, delay: Double = 0.15, from: CGSize = CGSize(width: 0, height: 12)) -> some View {
        modifier(PopIn(isActive: isActive, delay: delay, from: from))
    }
}

private let mockText = Font.system(size: 11, weight: .medium)
private let mockTextBold = Font.system(size: 11, weight: .semibold, design: .rounded)
private let mockCaption = Font.system(size: 9, weight: .medium)

// MARK: - Page 1 · Home

private struct WelcomeMockup: View {
    let isActive: Bool

    private let tiles: [(String, Color)] = [
        (ALIIcon.cart, ALIColors.shoppingAccent),
        (ALIIcon.cleaning, ALIColors.houseTasksAccent),
        (ALIIcon.dining, ALIColors.weeklyMenuAccent),
        (ALIIcon.calendar, ALIColors.familyAccent),
        (ALIIcon.bell, ALIColors.remindersAccent),
        (ALIIcon.euro, ALIColors.economiaAccent)
    ]

    var body: some View {
        MockPhone(title: "Home", accent: ALIColors.primary) {
            // "Today" card.
            HStack(spacing: 8) {
                ALIIconView(icon: ALIIcon.dining, size: 16, color: ALIColors.onAccent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Today")
                        .font(mockCaption)
                        .foregroundStyle(ALIColors.onAccent.opacity(0.7))
                    Text("Pasta carbonara")
                        .font(mockTextBold)
                        .foregroundStyle(ALIColors.onAccent)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(ALIColors.weeklyMenuAccent)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Feature grid.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                ForEach(tiles.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tiles[i].1.opacity(0.45))
                        .frame(height: 44)
                        .overlay(ALIIconView(icon: tiles[i].0, size: 20, color: ALIColors.ink))
                }
            }

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ALIColors.surfaceVariant)
                .frame(height: 26)
        }
    }
}

// MARK: - Page 2 · Shopping list

private struct ShoppingMockup: View {
    let isActive: Bool

    private let items: [(LocalizedStringKey, Bool)] = [
        ("Milk", true),
        ("Bread", false),
        ("Tomatoes", false),
        ("Olive oil", true),
        ("Eggs", false),
        ("Bananas", false),
        ("Coffee", true)
    ]

    var body: some View {
        MockPhone(title: "Shopping list", accent: ALIColors.shoppingAccent) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items.indices, id: \.self) { i in
                    let checked = items[i].1
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(checked ? ALIColors.success : ALIColors.surfaceVariant)
                                .frame(width: 16, height: 16)
                            if checked {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(ALIColors.onAccent)
                            }
                        }
                        Text(items[i].0)
                            .font(mockText)
                            .foregroundStyle(checked ? ALIColors.mutedInk : ALIColors.ink)
                            .strikethrough(checked)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        // Live update toast.
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                MockAvatar(initial: "L", color: ALIColors.remindersAccent, size: 18)
                Text("Lucía checked Milk")
                    .font(mockTextBold)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(ALIColors.surface, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .offset(x: -40, y: 26)
            .popIn(isActive, from: CGSize(width: -12, height: 0))
        }
    }
}

// MARK: - Page 3 · House tasks

private struct TasksMockup: View {
    let isActive: Bool

    private struct Chore {
        let name: LocalizedStringKey
        let status: LocalizedStringKey
        let color: Color
        let done: Bool
    }

    private let tasks: [Chore] = [
        Chore(name: "Take out the trash", status: "Done today · 👤 Dad", color: ALIColors.success, done: true),
        Chore(name: "Clean the bathroom", status: "Due soon · 5 days ago", color: ALIColors.sun, done: false),
        Chore(name: "Water the plants", status: "Up to date · 2 days ago", color: ALIColors.success, done: false),
        Chore(name: "Change the sheets", status: "Overdue · 9 days ago", color: ALIColors.error, done: false)
    ]

    var body: some View {
        MockPhone(title: "House tasks", accent: ALIColors.houseTasksAccent) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(tasks.indices, id: \.self) { i in
                    let task = tasks[i]
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(task.done ? ALIColors.success : ALIColors.surfaceVariant)
                                .frame(width: 16, height: 16)
                            if task.done {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(ALIColors.onAccent)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.name)
                                .font(mockText)
                                .foregroundStyle(ALIColors.ink)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Circle().fill(task.color).frame(width: 5, height: 5)
                                Text(task.status)
                                    .font(mockCaption)
                                    .foregroundStyle(ALIColors.mutedInk)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
                    }
                    .padding(.vertical, 7)
                    if i < tasks.count - 1 {
                        Divider().overlay(ALIColors.outline)
                    }
                }
            }
            .padding(.bottom, 30)
        }
        // "Done" toast from another member.
        .overlay(alignment: .bottomTrailing) {
            MockFloatingCard(color: ALIColors.houseTasksAccent, rotation: 3) {
                HStack(spacing: 8) {
                    ALIIconView(icon: ALIIcon.cleaning, size: 18, color: ALIColors.onAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Take out the trash")
                            .font(mockTextBold)
                            .foregroundStyle(ALIColors.onAccent)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            MockAvatar(initial: "D", color: ALIColors.familyAccent, size: 13)
                            Text("Dad · Done today")
                                .font(mockCaption)
                                .foregroundStyle(ALIColors.onAccent.opacity(0.75))
                        }
                    }
                }
            }
            .offset(x: 46, y: -4)
            .popIn(isActive, delay: 0.3)
        }
    }
}

// MARK: - Page 4 · Weekly menu (same layout as WeeklyMenuScreen's day rows)

private struct MenuMockup: View {
    let isActive: Bool

    private struct Day {
        let label: LocalizedStringKey
        let lunch: LocalizedStringKey
        let dinner: LocalizedStringKey
        var isToday = false
        var isPast = false
        var hasRecipe = false
    }

    private let days: [Day] = [
        Day(label: "Mon", lunch: "Lentils", dinner: "Omelette", isPast: true),
        Day(label: "Tue", lunch: "Paella", dinner: "Salad", isToday: true, hasRecipe: true),
        Day(label: "Wed", lunch: "Stew", dinner: "Pizza")
    ]

    var body: some View {
        MockPhone(title: "Weekly menu", accent: ALIColors.weeklyMenuAccent) {
            VStack(spacing: 0) {
                ForEach(days.indices, id: \.self) { i in
                    dayRow(days[i])
                    if i < days.count - 1 {
                        Divider().overlay(ALIColors.outline).padding(.leading, 10)
                    }
                }
            }
            .padding(.vertical, 2)
            .background(ALIColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.bottom, 4)
        }
        // "Cook" shortcut straight to the recipe.
        .overlay(alignment: .trailing) {
            Label("Cook", systemImage: "book.pages.fill")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(ALIColors.onAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ALIColors.recipesAccent, in: Capsule())
                .shadow(color: ALIColors.recipesAccent.opacity(0.6), radius: 8, y: 3)
                .rotationEffect(.degrees(4))
                .offset(x: 34, y: -4)
                .popIn(isActive, delay: 0.3, from: CGSize(width: 12, height: 0))
        }
    }

    private func dayRow(_ day: Day) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(day.label)
                    .font(mockTextBold)
                    .foregroundStyle(ALIColors.ink)
                if day.isToday {
                    Text("Today")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(ALIColors.onAccent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(ALIColors.primary, in: Capsule())
                }
                if day.isPast {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ALIColors.success)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(ALIColors.mutedInk.opacity(0.6))
            }
            mealLine("Lunch", day.lunch, accent: ALIColors.mealLunchAccent)
            mealLine("Dinner", day.dinner, accent: ALIColors.mealDinnerAccent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(day.isToday ? ALIColors.primary.opacity(0.14) : Color.clear)
        .overlay(alignment: .leading) {
            if day.isToday {
                Rectangle().fill(ALIColors.primary).frame(width: 3)
            }
        }
        .opacity(day.isPast ? 0.55 : 1)
    }

    private func mealLine(_ label: LocalizedStringKey, _ dish: LocalizedStringKey, accent: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(ALIColors.ink)
                .frame(width: 34)
                .padding(.vertical, 2)
                .background(accent.opacity(0.55), in: Capsule())
            Text(dish)
                .font(mockTextBold)
                .foregroundStyle(ALIColors.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Page 5 · Calendar + reminder

private struct CalendarMockup: View {
    let isActive: Bool

    /// Days with events (turquoise) and "today" (outlined), like FamilyCalendarMonthView.
    private let eventDays: Set<Int> = [3, 8, 12, 17, 22, 26]
    private let today = 12
    private let firstWeekdayOffset = 2 // month starts on Wednesday

    var body: some View {
        MockPhone(title: "Calendar", accent: ALIColors.familyAccent) {
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                ForEach(0..<5, id: \.self) { row in
                    GridRow {
                        ForEach(0..<7, id: \.self) { col in
                            dayCell(row * 7 + col - firstWeekdayOffset + 1)
                        }
                    }
                }
            }

            VStack(spacing: 0) {
                eventRow(ALIIcon.doctor, "Dentist", "12 Oct, 17:00 · Mum")
                Divider().overlay(ALIColors.outline)
                eventRow(ALIIcon.cake, "Grandma's birthday", "17 Oct · All day")
            }
            .padding(.bottom, 8)
        }
        // Reminder notification.
        .overlay(alignment: .topTrailing) {
            MockFloatingCard(color: ALIColors.remindersAccent, rotation: 3) {
                HStack(spacing: 6) {
                    ALIIconView(icon: ALIIcon.bell, size: 14, color: ALIColors.onAccent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Pay the gas bill")
                            .font(mockTextBold)
                            .foregroundStyle(ALIColors.onAccent)
                        Text("Tomorrow, 10:00")
                            .font(mockCaption)
                            .foregroundStyle(ALIColors.onAccent.opacity(0.75))
                    }
                }
            }
            .offset(x: 44, y: -14)
            .popIn(isActive, delay: 0.3, from: CGSize(width: 12, height: 0))
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Int) -> some View {
        if day < 1 || day > 31 {
            Color.clear.frame(width: 21, height: 21)
        } else {
            Text(verbatim: "\(day)")
                .font(.system(size: 9, weight: day == today ? .bold : .medium, design: .rounded))
                .foregroundStyle(ALIColors.ink)
                .frame(width: 21, height: 21)
                .background(eventDays.contains(day) ? ALIColors.calendarActivity.opacity(0.55) : Color.clear)
                .clipShape(Circle())
                .overlay(Circle().stroke(day == today ? ALIColors.familyAccent : .clear, lineWidth: 1.5))
        }
    }

    private func eventRow(_ icon: String, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            ALIIconView(icon: icon, size: 15, fallback: ALIIcon.calendar)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(mockText)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(mockCaption)
                    .foregroundStyle(ALIColors.mutedInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Page 6 · Finances + history

private struct EconomyMockup: View {
    let isActive: Bool

    private let expenses: [(String, LocalizedStringKey, Double, String, Color)] = [
        (ALIIcon.cart, "Groceries", 86.40, "M", ALIColors.peopleAccent),
        (ALIIcon.bulb, "Electricity", 54.10, "D", ALIColors.familyAccent),
        (ALIIcon.car, "Fuel", 60.00, "D", ALIColors.familyAccent)
    ]

    private let split: [(Color, CGFloat)] = [
        (ALIColors.economiaAccent, 0.42),
        (ALIColors.shoppingAccent, 0.26),
        (ALIColors.familyAccent, 0.2),
        (ALIColors.recipesAccent, 0.12)
    ]

    var body: some View {
        MockPhone(title: "Finances", accent: ALIColors.economiaAccent) {
            VStack(alignment: .leading, spacing: 2) {
                Text("This month")
                    .font(mockCaption)
                    .foregroundStyle(ALIColors.mutedInk)
                Text(482.30, format: .currency(code: "EUR"))
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(ALIColors.ink)
            }

            // Spending by category.
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(split.indices, id: \.self) { i in
                        split[i].0.frame(width: max(0, geo.size.width * split[i].1 - 2))
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())

            VStack(spacing: 7) {
                ForEach(expenses.indices, id: \.self) { i in
                    let e = expenses[i]
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(ALIColors.economiaAccent.opacity(0.45))
                            .frame(width: 22, height: 22)
                            .overlay(ALIIconView(icon: e.0, size: 13, color: ALIColors.ink))
                        Text(e.1)
                            .font(mockText)
                            .foregroundStyle(ALIColors.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(e.2, format: .currency(code: "EUR"))
                            .font(mockTextBold)
                            .foregroundStyle(ALIColors.ink)
                        MockAvatar(initial: e.3, color: e.4, size: 14)
                    }
                }
            }
            .padding(.bottom, 48)
        }
        // History sheet, same rows as HistorialSheet.
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                Text("History")
                    .font(mockTextBold)
                    .foregroundStyle(ALIColors.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
                historyRow("plus.circle.fill", ALIColors.houseTasksAccent, "Dad created \"Electricity\"", "Finances · 18:40")
                Divider().overlay(ALIColors.outline)
                historyRow("pencil.circle.fill", ALIColors.economiaAccent, "Mum edited \"Groceries\"", "Finances · 12:15")
            }
            .padding(10)
            .frame(width: 176)
            .background(ALIColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ALIColors.outline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
            .rotationEffect(.degrees(3))
            .offset(x: 52, y: 10)
            .popIn(isActive, delay: 0.3)
        }
    }

    private func historyRow(_ icon: String, _ color: Color, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(mockText)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(mockCaption)
                    .foregroundStyle(ALIColors.mutedInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    AppIntroView(onFinish: {})
}
