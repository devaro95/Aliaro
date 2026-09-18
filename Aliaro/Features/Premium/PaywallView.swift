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

    /// Cloud backup first -- it's the feature that matters most (losing
    /// your group's data on reinstall is the scariest thing Premium
    /// prevents), everything else keeps its normal order after it.
    private var lockedFeatures: [PremiumFeature] {
        var features = PremiumFeature.allCases.filter { premium.config.isPremium($0) }
        if let cloudIndex = features.firstIndex(of: .cloudBackup) {
            let cloud = features.remove(at: cloudIndex)
            features.insert(cloud, at: 0)
        }
        return features
    }

    /// e.g. "3-month free trial", read straight from the product's
    /// introductory offer so it always matches whatever's configured in
    /// App Store Connect (or the local StoreKit config while debugging).
    private func trialText(for product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let units = offer.period.value * offer.periodCount
        let unitName: String
        switch offer.period.unit {
        case .day: unitName = units == 1 ? "day" : "days"
        case .week: unitName = units == 1 ? "week" : "weeks"
        case .month: unitName = units == 1 ? "month" : "months"
        case .year: unitName = units == 1 ? "year" : "years"
        @unknown default: unitName = "period"
        }
        return "\(units)-\(unitName) free trial"
    }

    /// Combines a plan's own subtitle (e.g. "Best value") with its trial
    /// text, when it has one, separated by a dot.
    private func planSubtitle(for product: Product, fallback: String?) -> LocalizedStringKey? {
        let trial = trialText(for: product)
        switch (fallback, trial) {
        case let (f?, t?): return "\(f) · \(t)"
        case let (f?, nil): return "\(f)"
        case let (nil, t?): return "\(t)"
        case (nil, nil): return nil
        }
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
                VStack(spacing: 16) {
                    header
                    if !lockedFeatures.isEmpty {
                        featuresCard
                    }
                    plansPicker
                    ALIPrimaryButton(
                        text: isPurchasing ? "Processing…" : "Continue",
                        enabled: !isPurchasing && selectedProduct != nil,
                        accent: ALIColors.economiaAccent,
                        action: purchase
                    )
                    ALITextButton(text: "Restore purchases", action: restore)
                    legalFooter
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(ALIColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await premium.subscriptions.loadProducts() }
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
            VStack(alignment: .leading, spacing: 10) {
                ForEach(lockedFeatures) { feature in
                    HStack(spacing: 12) {
                        Image(systemName: feature.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ALIColors.economiaAccent)
                            .frame(width: 24)
                        Text(feature.title)
                            .font(ALITypography.bodyMedium)
                            .foregroundStyle(ALIColors.ink)
                        Spacer()
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(ALIColors.success)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var plansPicker: some View {
        if premium.subscriptions.isLoadingProducts && monthlyProduct == nil && yearlyProduct == nil {
            ProgressView().padding(.vertical, 20)
        } else {
            VStack(spacing: 10) {
                if let yearlyProduct {
                    planRow(
                        title: "Yearly",
                        price: yearlyProduct.displayPrice,
                        subtitle: planSubtitle(
                            for: yearlyProduct,
                            fallback: nil
                        ),
                        badge: "Best value · \(monthlyEquivalent(for: yearlyProduct))/month",
                        isSelected: selectedPlan == .yearly
                    ) { selectedPlan = .yearly }
                }
                if let monthlyProduct {
                    planRow(
                        title: "Monthly",
                        price: "\(monthlyProduct.displayPrice)/month",
                        subtitle: planSubtitle(
                            for: monthlyProduct,
                            fallback: nil
                        ),
                        isSelected: selectedPlan == .monthly
                    ) { selectedPlan = .monthly }
                }
            }
        }
    }

    private func planRow(
        title: LocalizedStringKey,
        price: String,
        subtitle: LocalizedStringKey?,
        badge: LocalizedStringKey? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(ALITypography.titleLarge)
                        .foregroundStyle(ALIColors.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.economiaAccent)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(price)
                        .font(ALITypography.titleLarge)
                        .foregroundStyle(ALIColors.ink)
                    if let badge {
                        Text(badge)
                            .font(ALITypography.labelLarge)
                            .foregroundStyle(ALIColors.economiaAccent)
                    }
                }
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? ALIColors.economiaAccent : ALIColors.mutedInk)
            }
            .padding(16)
            .background(ALIColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? ALIColors.economiaAccent : ALIColors.outline, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
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
        Task {
            defer { isPurchasing = false }
            do {
                try await premium.subscriptions.purchase(product, appAccountToken: FamilySession.shared.memberID)
                // Explicit dismiss right after a confirmed purchase, in
                // addition to the .onChange below -- don't rely on the
                // observed-property update alone to close the sheet.
                if premium.subscriptions.isSubscribed { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restore() {
        Task {
            do { try await premium.subscriptions.restorePurchases() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
