import SwiftUI
import StoreKit

/// Sheet shown whenever someone taps something premium: what Aliaro
/// Premium unlocks (built live from whatever `PremiumConfig` currently
/// marks as premium, so it never drifts from what's actually gated) plus
/// the monthly/yearly purchase buttons.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var premium: PremiumManager

    private enum Plan { case monthly, yearly }
    @State private var selectedPlan: Plan = .yearly
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    /// Real number of people using Aliaro (`public_member_count` RPC).
    /// Only shown once it's big enough to be worth bragging about.
    @State private var userCount: Int?
    /// Apple only grants the intro trial once per subscription group, so
    /// the copy about the trial is hidden for people who already used it.
    @State private var isTrialEligible = true

    // Analytics: what opened this paywall, when, and how it ended.
    @State private var trigger = Track.pendingPaywallTrigger
    @State private var openedAt = Date.now
    @State private var didPurchase = false
    @State private var purchaseAttempts = 0
    @State private var closedWithButton = false

    private func planKey(_ plan: Plan) -> String { plan == .monthly ? "monthly" : "yearly" }

    /// Common params for every paywall event.
    private func paywallParams(_ extra: [String: Any?] = [:]) -> [String: Any?] {
        var params: [String: Any?] = [
            "trigger": trigger,
            "plan": planKey(selectedPlan),
            "product_id": selectedProduct?.id,
            "price": selectedProduct.map { NSDecimalNumber(decimal: $0.price).doubleValue },
            "currency": selectedProduct?.priceFormatStyle.currencyCode,
            "seconds_open": Int(Date.now.timeIntervalSince(openedAt))
        ]
        extra.forEach { params[$0.key] = $0.value }
        return params
    }

    private var lockedFeatures: [PremiumFeature] {
        PremiumFeature.allCases.filter { premium.config.isPremium($0) }
    }

    private struct FeatureRow: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
        let systemImage: String
        let accent: Color
    }

    /// Pairs of related features shown as a single paywall row when both
    /// are premium, to keep the list short: the row takes the first
    /// feature's place and icon.
    private static let mergedRows: [(first: PremiumFeature, second: PremiumFeature, title: LocalizedStringKey, subtitle: LocalizedStringKey)] = [
        (.houseTasksStats, .economiaStats, "Task and finance statistics",
         "See who does the most at home and where your money goes."),
        (.unlimitedReminders, .unlimitedHouseTasks, "Unlimited reminders and house tasks",
         "Add everything your family needs, with no limits.")
    ]

    /// `lockedFeatures` as paywall rows, with `mergedRows` applied.
    private var featureRows: [FeatureRow] {
        let features = lockedFeatures
        let merges = Self.mergedRows.filter { features.contains($0.first) && features.contains($0.second) }
        return features.compactMap { feature in
            if merges.contains(where: { $0.second == feature }) { return nil }
            if let merge = merges.first(where: { $0.first == feature }) {
                return FeatureRow(id: feature.rawValue, title: merge.title, subtitle: merge.subtitle,
                                  systemImage: feature.systemImage, accent: feature.accent)
            }
            return FeatureRow(id: feature.rawValue, title: feature.title, subtitle: feature.subtitle,
                              systemImage: feature.systemImage, accent: feature.accent)
        }
    }

    /// e.g. "3 months", localized, read straight from the product's
    /// introductory offer so it always matches whatever's configured in
    /// App Store Connect (or the local StoreKit config while debugging).
    /// nil when there's no free trial or the user isn't eligible anymore.
    private func trialDuration(for product: Product) -> String? {
        guard isTrialEligible,
              let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let units = offer.period.value * offer.periodCount
        var components = DateComponents()
        switch offer.period.unit {
        case .day: components.day = units
        case .week: components.weekOfMonth = units
        case .month: components.month = units
        case .year: components.year = units
        @unknown default: return nil
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = [.day, .weekOfMonth, .month, .year]
        return formatter.string(from: components)
    }

    /// e.g. "3 months free trial".
    private func trialText(for product: Product) -> String? {
        trialDuration(for: product).map { String(localized: "\($0) free trial") }
    }

    /// What the yearly plan works out to per month, so the saving against
    /// the monthly price is obvious at a glance.
    private func monthlyEquivalent(for yearlyProduct: Product) -> String {
        let perMonth = yearlyProduct.price / 12
        return yearlyProduct.priceFormatStyle.format(perMonth)
    }

    private var monthlyProduct: Product? { premium.subscriptions.monthlyProduct }
    private var yearlyProduct: Product? { premium.subscriptions.yearlyProduct }
    private var selectedProduct: Product? { selectedPlan == .monthly ? monthlyProduct : yearlyProduct }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    if let socialProofText {
                        socialProof(socialProofText)
                    }
                    if !lockedFeatures.isEmpty {
                        featuresCard
                    }
                    howItWorks
                    plansPicker
                    perks
                    faq
                    indieNote
                    ALITextButton(text: "Restore purchases", action: restore)
                    legalFooter
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.visible)
            // CTA pinned to the bottom so it's always one tap away while
            // the user scrolls through everything above.
            .safeAreaInset(edge: .bottom) { stickyCTA }
            .background(ALIColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { closedWithButton = true; dismiss() }
                }
            }
            .task {
                async let count: Void = loadUserCount()
                await premium.subscriptions.loadProducts()
                if let subscription = (yearlyProduct ?? monthlyProduct)?.subscription {
                    isTrialEligible = await subscription.isEligibleForIntroOffer
                }
                await count
            }
            .onAppear {
                trigger = Track.pendingPaywallTrigger
                openedAt = .now
                Track.screen("paywall")
                Track.event("paywall_open", [
                    "trigger": trigger,
                    "locked_features": lockedFeatures.count,
                    "default_plan": planKey(selectedPlan)
                ])
            }
            .onDisappear {
                Track.event("paywall_close", paywallParams([
                    "converted": didPurchase,
                    "purchase_attempts": purchaseAttempts,
                    "method": closedWithButton ? "close_button" : (didPurchase ? "purchased" : "swipe")
                ]))
            }
            .onChange(of: selectedPlan) { _, _ in
                Track.event("paywall_plan_selected", paywallParams())
            }
            .alert(
                "Couldn't complete the purchase",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: premium.subscriptions.isSubscribed) { _, isSubscribed in
                if isSubscribed { dismiss() }
            }
        }
        .presentationDetents([.large])
    }

    /// Matches the wordmark's own letter style (same size/weight/design)
    /// so "Premium" reads as part of the same lockup — no salmon dot on
    /// its own "i", that treatment is specific to the "Aliaro" wordmark
    /// and would misalign here.
    private static let wordmarkSize: CGFloat = 28

    private var header: some View {
        VStack(spacing: 10) {
            // Same crown as the premium badges across the app, just bigger.
            Image(systemName: "crown.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(ALIColors.onAccent)
                .frame(width: 60, height: 60)
                .background(ALIColors.sun)
                .clipShape(Circle())
                .padding(.bottom, 4)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                AliaroWordmark(size: Self.wordmarkSize)
                Text("Premium")
                    .font(.system(size: Self.wordmarkSize, weight: .black, design: .rounded))
                    .foregroundStyle(ALIColors.ink)
            }
            Text("One subscription unlocks everything for your whole family group.")
                .font(ALITypography.bodyMedium)
                .foregroundStyle(ALIColors.mutedInk)
                .multilineTextAlignment(.center)
        }
    }

    private var featuresCard: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Everything included in Premium")
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)
                    .padding(.bottom, 18)
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(featureRows) { feature in
                        HStack(alignment: .center, spacing: 14) {
                            Image(systemName: feature.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(ALIColors.onAccent)
                                .frame(width: 44, height: 44)
                                .background(feature.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(feature.title)
                                    .font(ALITypography.bodyLarge.weight(.semibold))
                                    .foregroundStyle(ALIColors.ink)
                                Text(feature.subtitle)
                                    .font(ALITypography.bodyMedium)
                                    .foregroundStyle(ALIColors.mutedInk)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(ALIColors.success)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Social proof

    /// "More than 1,000 people…" rounded *down* from the real count, and
    /// hidden until there are at least 100 so the claim is always true.
    private var socialProofText: LocalizedStringKey? {
        guard let userCount, userCount >= 100 else { return nil }
        let step = userCount >= 1_000 ? 1_000 : 100
        let rounded = (userCount / step) * step
        return "More than \(rounded.formatted(.number)) people already use Aliaro"
    }

    private func socialProof(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: -8) {
                ForEach(Array([ALIColors.primary, ALIPalette.lavender, ALIPalette.mint].enumerated()), id: \.offset) { _, color in
                    Image(systemName: "person.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ALIColors.onAccent)
                        .frame(width: 26, height: 26)
                        .background(color)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(ALIColors.surface, lineWidth: 2))
                }
            }
            Text(text)
                .font(ALITypography.labelLarge.weight(.semibold))
                .foregroundStyle(ALIColors.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .background(ALIColors.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(ALIColors.outline, lineWidth: 1))
    }

    private func loadUserCount() async {
        do {
            let count: Int = try await supabase.rpc("public_member_count").execute().value
            userCount = count
        } catch {
            print("⚠️ Could not fetch public_member_count (\(error))")
        }
    }

    // MARK: - How it works (vertical roadmap)

    private struct Step: Identifiable {
        let id: Int
        let icon: String
        let color: Color
        let title: LocalizedStringKey
        let text: LocalizedStringKey
    }

    private var steps: [Step] {
        let trial = selectedProduct.flatMap(trialDuration(for:))
            ?? yearlyProduct.flatMap(trialDuration(for:))
            ?? monthlyProduct.flatMap(trialDuration(for:))
        return [
            Step(id: 1, icon: "hand.tap.fill", color: ALIColors.primary,
                 title: "Choose your plan",
                 text: "Yearly or monthly, whatever suits your family best."),
            trial.map { _ in
                Step(id: 2, icon: "gift.fill", color: ALIPalette.lavender,
                     title: "Try it free",
                     text: "Everything unlocked for your whole family group.")
            } ?? Step(id: 2, icon: "sparkles", color: ALIPalette.lavender,
                      title: "Enjoy it from day one",
                      text: "Everything unlocked for your whole family group."),
            trial != nil
                ? Step(id: 3, icon: "checkmark.seal.fill", color: ALIPalette.mint,
                       title: "Keep it or cancel",
                       text: "Cancel before the trial ends and you won't be charged anything.")
                : Step(id: 3, icon: "checkmark.seal.fill", color: ALIPalette.mint,
                       title: "Cancel anytime",
                       text: "No commitment: manage it from your Apple ID settings.")
        ]
    }

    private var howItWorks: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 0) {
                Text("How it works")
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)
                    .padding(.bottom, 16)
                ForEach(steps) { step in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Image(systemName: step.icon)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(ALIColors.onAccent)
                                .frame(width: 36, height: 36)
                                .background(step.color)
                                .clipShape(Circle())
                            if step.id != steps.count {
                                Rectangle()
                                    .fill(ALIColors.outline)
                                    .frame(width: 2)
                                    .frame(maxHeight: .infinity)
                                    .padding(.vertical, 4)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("STEP \(step.id)")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(ALIColors.mutedInk)
                            Text(step.title)
                                .font(ALITypography.titleLarge)
                                .foregroundStyle(ALIColors.ink)
                            Text(step.text)
                                .font(ALITypography.bodyMedium)
                                .foregroundStyle(ALIColors.mutedInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 2)
                        .padding(.bottom, step.id != steps.count ? 18 : 0)
                        Spacer(minLength: 0)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Yearly saving vs paying monthly for 12 months, e.g. 37.
    private var yearlySavingsPercent: Int? {
        guard let yearlyProduct, let monthlyProduct, monthlyProduct.price > 0 else { return nil }
        let ratio = NSDecimalNumber(decimal: yearlyProduct.price / (monthlyProduct.price * 12)).doubleValue
        let percent = Int(((1 - ratio) * 100).rounded(.down))
        return percent > 0 ? percent : nil
    }

    @ViewBuilder
    private var plansPicker: some View {
        if premium.subscriptions.isLoadingProducts && monthlyProduct == nil && yearlyProduct == nil {
            ProgressView().padding(.vertical, 20)
        } else {
            VStack(spacing: 14) {
                if let yearlyProduct {
                    planRow(
                        title: "Yearly",
                        price: yearlyProduct.displayPrice,
                        period: "/year",
                        highlight: yearlySavingsPercent.map { (percent: Int) -> LocalizedStringKey in "Save \(percent)%" } ?? "Best value",
                        note: "Only \(monthlyEquivalent(for: yearlyProduct))/month",
                        trial: trialText(for: yearlyProduct),
                        isSelected: selectedPlan == .yearly
                    ) { selectedPlan = .yearly }
                }
                if let monthlyProduct {
                    planRow(
                        title: "Monthly",
                        price: monthlyProduct.displayPrice,
                        period: "/month",
                        highlight: nil,
                        note: "Maximum flexibility",
                        trial: trialText(for: monthlyProduct),
                        isSelected: selectedPlan == .monthly
                    ) { selectedPlan = .monthly }
                }
            }
        }
    }

    private func planRow(
        title: LocalizedStringKey,
        price: String,
        period: LocalizedStringKey,
        highlight: LocalizedStringKey?,
        note: LocalizedStringKey?,
        trial: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? ALIColors.primary : ALIColors.mutedInk)
                    Text(title)
                        .font(ALITypography.titleLarge)
                        .foregroundStyle(ALIColors.ink)
                    Spacer()
                    if let highlight {
                        Text(highlight)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(ALIColors.onAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(ALIColors.sun)
                            .clipShape(Capsule())
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(price)
                        .font(ALITypography.headlineLarge)
                        .foregroundStyle(ALIColors.ink)
                    Text(period)
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                    Spacer()
                    if let note {
                        Text(note)
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.mutedInk)
                    }
                }
                if let trial {
                    Label(trial, systemImage: "gift.fill")
                        .font(ALITypography.labelLarge.weight(.semibold))
                        .foregroundStyle(ALIColors.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(ALIColors.primary.opacity(0.25))
                        .clipShape(Capsule())
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? ALIColors.primary.opacity(0.08) : Color.clear)
            .background(ALIColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? ALIColors.primary : ALIColors.outline, lineWidth: isSelected ? 2 : 1)
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reassurance

    private var perks: some View {
        HStack(spacing: 10) {
            perk(icon: "lock.shield.fill", color: ALIPalette.sky, text: "Secure payment with Apple")
            perk(icon: "arrow.uturn.backward.circle.fill", color: ALIPalette.mint, text: "No commitment")
            perk(icon: "person.3.fill", color: ALIPalette.rose, text: "Whole family included")
        }
    }

    private func perk(icon: String, color: Color, text: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(ALIColors.onAccent)
                .frame(width: 40, height: 40)
                .background(color)
                .clipShape(Circle())
            Text(text)
                .font(ALITypography.labelLarge.weight(.semibold))
                .foregroundStyle(ALIColors.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .background(ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var hasTrial: Bool {
        [yearlyProduct, monthlyProduct].compactMap { $0 }.contains { trialDuration(for: $0) != nil }
    }

    private var faq: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 4) {
                Text("Frequently asked questions")
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)
                    .padding(.bottom, 8)
                faqItem("Is it shared with my family?",
                        "Yes. One subscription unlocks Premium for everyone in your family group.")
                Divider().overlay(ALIColors.outline)
                faqItem("When will I be charged?",
                        hasTrial
                            ? "Only when the free trial ends. If you cancel before then, you pay nothing."
                            : "When you subscribe, and then automatically every period until you cancel.")
                Divider().overlay(ALIColors.outline)
                faqItem("How do I cancel?",
                        "Whenever you want from Settings › Apple ID › Subscriptions. You keep Premium until the end of the period you've paid for.")
            }
        }
    }

    private func faqItem(_ question: LocalizedStringKey, _ answer: LocalizedStringKey) -> some View {
        DisclosureGroup {
            Text(answer)
                .font(ALITypography.bodyMedium)
                .foregroundStyle(ALIColors.mutedInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        } label: {
            Text(question)
                .font(ALITypography.bodyMedium.weight(.semibold))
                .foregroundStyle(ALIColors.ink)
        }
        .tint(ALIColors.mutedInk)
        .padding(.vertical, 8)
    }

    private var indieNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(ALIColors.error)
            Text("Made in Madrid by an independent developer. Your subscription helps Aliaro keep growing.")
                .font(ALITypography.bodyMedium)
                .foregroundStyle(ALIColors.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ALIColors.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Sticky CTA

    private var stickyCTA: some View {
        VStack(spacing: 6) {
            ALIPrimaryButton(
                text: isPurchasing ? "Processing…" : (selectedProduct.flatMap(trialDuration(for:)) != nil ? "Start free trial" : "Continue"),
                enabled: !isPurchasing && selectedProduct != nil,
                accent: ALIColors.primary,
                action: purchase
            )
            if let product = selectedProduct {
                let period = selectedPlan == .yearly ? String(localized: "/year") : String(localized: "/month")
                Group {
                    if let duration = trialDuration(for: product) {
                        Text("Free for \(duration), then \(product.displayPrice)\(period)")
                    } else {
                        Text("\(product.displayPrice)\(period) · Cancel anytime")
                    }
                }
                .font(ALITypography.labelLarge)
                .foregroundStyle(ALIColors.mutedInk)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(ALIColors.background.shadow(.drop(color: .black.opacity(0.06), radius: 8, y: -2)))
    }

    private var legalFooter: some View {
        Text("Cancel anytime in your Apple ID subscription settings.")
            .font(ALITypography.labelLarge)
            .foregroundStyle(ALIColors.mutedInk)
            .multilineTextAlignment(.center)
    }

    private func purchase() {
        guard let product = selectedProduct else { return }
        isPurchasing = true
        purchaseAttempts += 1
        Track.event("paywall_purchase_tap", paywallParams(["has_trial": trialText(for: product) != nil]))
        Task {
            defer { isPurchasing = false }
            do {
                let outcome = try await premium.subscriptions.purchase(product, appAccountToken: FamilySession.shared.memberID)
                switch outcome {
                case .success:
                    didPurchase = true
                    Track.event("paywall_purchase_success", paywallParams())
                case .cancelled:
                    Track.event("paywall_purchase_cancel", paywallParams())
                }
                // Explicit dismiss right after a confirmed purchase, in
                // addition to the .onChange below -- don't rely on the
                // observed-property update alone to close the sheet.
                if premium.subscriptions.isSubscribed { dismiss() }
            } catch {
                if case SubscriptionError.pending = error {
                    Track.event("paywall_purchase_pending", paywallParams())
                } else {
                    Track.event("paywall_purchase_error", paywallParams(["error": String(describing: error)]))
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restore() {
        Track.event("paywall_restore_tap", paywallParams())
        Task {
            do {
                try await premium.subscriptions.restorePurchases()
                Track.event("paywall_restore_result", paywallParams(["restored": premium.subscriptions.isSubscribed]))
                if premium.subscriptions.isSubscribed { didPurchase = true }
            } catch {
                Track.event("paywall_restore_error", paywallParams(["error": String(describing: error)]))
                errorMessage = error.localizedDescription
            }
        }
    }
}
