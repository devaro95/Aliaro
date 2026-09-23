import SwiftUI

/// One-time welcome carousel shown the very first time the app runs on a
/// device, before `FamilyOnboardingView` (create/join group). Purely
/// informational — introduces what Aliaro does — and is never shown again
/// once dismissed (tracked by `FamilySession.hasSeenAppIntro`), including
/// after leaving a family group later on.
struct AppIntroView: View {
    let onFinish: () -> Void

    @State private var page = 0

    private let pages: [IntroPage] = [
        IntroPage(
            emoji: "🏡",
            title: "Welcome to Aliaro",
            subtitle: "Organize your home life as a family, all in one shared space.",
            accent: ALIColors.familyAccent
        ),
        IntroPage(
            emoji: "🛒",
            title: "Shopping & tasks",
            subtitle: "Keep a shared shopping list and split house tasks, updated in real time for everyone.",
            accent: ALIColors.houseTasksAccent
        ),
        IntroPage(
            emoji: "🍽️",
            title: "Menu, calendar & reminders",
            subtitle: "Plan the weekly menu, family calendar and reminders together.",
            accent: ALIColors.weeklyMenuAccent
        ),
        IntroPage(
            emoji: "💶",
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
                    IntroPageView(page: introPage, showWordmark: index == 0)
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
    let emoji: String
    let title: String
    let subtitle: String
    let accent: Color
}

private struct IntroPageView: View {
    let page: IntroPage
    var showWordmark: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Circle()
                .fill(page.accent.opacity(0.25))
                .frame(width: 140, height: 140)
                .overlay(Text(page.emoji).font(.system(size: 64)))

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
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }
}
