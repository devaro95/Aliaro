import SwiftUI

/// "What's new" shown once after updating the app, over the main tabs,
/// with what this release adds. People who install the app now (they
/// create or join a group on this version) don't see it: there's nothing
/// "new" for them.
///
/// For a new release: bump `release` and change `slides`. The debug menu
/// can show it again any time.
@MainActor
final class WhatsNew: ObservableObject {
    static let shared = WhatsNew()

    /// Id of this content (not the build number, so Dev builds show it too).
    /// "1.3.0" was already used by the previous news (shipped in 1.2.x), hence the suffix.
    static let release = "1.3.0-places-map-menu"

    @Published var isPresented = false

    private static let seenKey = "aliaro.whatsNew.seenRelease"
    private let defaults = UserDefaults.standard

    /// Main tabs on screen: show it if this device hasn't seen this release's yet.
    func showIfNeeded() {
        guard defaults.string(forKey: Self.seenKey) != Self.release else { return }
        markSeen()
        Track.event("whats_new_shown", ["screen": "app_update", "release": Self.release])
        // A beat so it lands after the tabs appear.
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            isPresented = true
        }
    }

    /// Group created or joined on this version: nothing to announce to them.
    func markSeen() {
        defaults.set(Self.release, forKey: Self.seenKey)
    }

    /// Debug menu: show it now (after the debug sheet closes).
    func debugShow() {
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            isPresented = true
        }
    }

    /// One page per new feature, each with a drawn illustration (sample data, no assets).
    static let slides: [WhatsNewSlide] = [
        WhatsNewSlide(
            id: "places", illustration: .places, title: "Family places",
            text: "Save your family's favourite spots on a map and get there in a tap.",
            accent: ALIColors.placesAccent
        ),
        WhatsNewSlide(
            id: "world_map", illustration: .worldMap, title: "World map",
            text: "Mark the countries you've visited and watch the family map fill up.",
            accent: ALIColors.worldMapAccent
        ),
        WhatsNewSlide(
            id: "menu", illustration: .menu, title: "Weekly menu",
            text: "Plan the menu for any week, past or future, with several dishes per meal and the whole month at a glance.",
            accent: ALIColors.weeklyMenuAccent
        ),
    ]
}

struct WhatsNewSlide: Identifiable {
    enum Illustration { case places, worldMap, menu }

    let id: String
    let illustration: Illustration
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    let accent: Color
}

/// The sheet with this release's news: a carousel, one page per feature.
struct WhatsNewSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private let slides = WhatsNew.slides
    private var isLast: Bool { page == slides.count - 1 }

    /// "New in Aliaro" with the logo's "Aliaro" (salmon-dot "i").
    private var title: Text {
        let size = ALIWhatsNewSheet.bigTitleSize
        let wordmark = Text(AliaroWordmark.inlineImage(size: size, colorScheme: colorScheme))
            .baselineOffset(AliaroWordmark.inlineBaselineOffset(size: size))
        return Text("New in \(wordmark)")
    }

    var body: some View {
        VStack(spacing: 20) {
            title
                .font(.system(size: ALIWhatsNewSheet.bigTitleSize, weight: .black, design: .rounded))
                .foregroundStyle(ALIColors.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 44)
                .padding(.horizontal, 20)

            TabView(selection: $page) {
                ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                    WhatsNewSlideView(slide: slide).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            pageDots

            ALIPrimaryButton(text: isLast ? "Got it" : "Next", accent: slides[page].accent) {
                if isLast {
                    dismiss()
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) { page += 1 }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(ALIColors.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: page) { _, new in
            Track.event("whats_new_slide", ["slide": slides[new].id, "release": WhatsNew.release])
        }
        .trackScreen("whats_new_update")
    }

    /// One dot per page; the current one is a wider capsule in its feature's color.
    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(slides.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? slides[index].accent : ALIColors.outline)
                    .frame(width: index == page ? 22 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: page)
        .accessibilityHidden(true)
    }
}

/// A carousel page: the illustration in a rounded card, then the title and text.
private struct WhatsNewSlideView: View {
    let slide: WhatsNewSlide

    var body: some View {
        VStack(spacing: 18) {
            illustration
                .frame(maxWidth: .infinity)
                .frame(height: 310)
                .background(ALIColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(slide.accent, lineWidth: 2)
                )
                .allowsHitTesting(false) // swipes go to the carousel
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(slide.title)
                    .font(ALITypography.headlineMedium)
                    .foregroundStyle(ALIColors.ink)
                Text(slide.text)
                    .font(ALITypography.bodyLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var illustration: some View {
        switch slide.illustration {
        case .places:
            SampleMapBackdrop()
        case .worldMap:
            WorldGlobe(colorFor: { WhatsNewSamples.countries.contains($0) ? MapColors.everyone : nil })
                .padding(.vertical, 8)
        case .menu:
            WhatsNewMenuMonth()
        }
    }
}

private enum WhatsNewSamples {
    /// Sample visits for the World map page (not saved anywhere).
    static let countries: Set<String> = ["ES", "PT", "FR", "IT", "GB", "DE", "MA", "US", "MX", "AR", "JP"]
}

/// The menu's month view with a sample, mostly-planned month (the same as its premium preview).
private struct WhatsNewMenuMonth: View {
    private var monthStart: Date { MenuCalendar.startOfMonth(.now) }

    /// Leading blanks up to Monday, then each day of this month.
    private var cells: [Date?] {
        let firstWeekStart = MenuCalendar.startOfWeek(monthStart)
        let leading = MenuCalendar.calendar.dateComponents([.day], from: firstWeekStart, to: monthStart).day ?? 0
        let count = MenuCalendar.calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let days = (0..<count).map { Optional(MenuCalendar.adding(days: $0, to: monthStart)) }
        return Array(repeating: nil, count: leading) + days
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        let symbols = MenuCalendar.weekdaySymbols
        let cells = cells
        VStack(alignment: .leading, spacing: 4) {
            Text(monthStart.formatted(.dateTime.month(.wide).year()).capitalized)
                .font(ALITypography.titleLarge)
                .foregroundStyle(ALIColors.ink)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(symbols.indices, id: \.self) { index in
                    Text(symbols[index].uppercased())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ALIColors.mutedInk)
                }
                ForEach(cells.indices, id: \.self) { index in
                    if let date = cells[index] {
                        cell(date)
                    } else {
                        Color.clear.frame(height: 32)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                legendDot(ALIColors.mealLunchAccent, "Lunch")
                legendDot(ALIColors.mealDinnerAccent, "Dinner")
            }
        }
        .padding(14)
    }

    private func cell(_ date: Date) -> some View {
        let sample = MenuDemoData.planned(on: date)
        let isToday = MenuCalendar.isSameDay(date, .now)
        let empty = ALIColors.outline.opacity(0.5)
        return VStack(spacing: 3) {
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 13, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? ALIColors.onAccent : ALIColors.ink)
                .frame(width: 22, height: 22)
                .background(isToday ? ALIColors.primary : Color.clear)
                .clipShape(Circle())
            HStack(spacing: 2) {
                Circle().fill(sample.lunch ? ALIColors.mealLunchAccent : empty).frame(width: 5, height: 5)
                Circle().fill(sample.dinner ? ALIColors.mealDinnerAccent : empty).frame(width: 5, height: 5)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32)
    }

    private func legendDot(_ color: Color, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.mutedInk)
        }
    }
}
