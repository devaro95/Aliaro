import SwiftUI

/// Rounded card with a soft border — base building block of Aliaro's visual language.
struct ALICard<Content: View>: View {
    var containerColor: Color = ALIColors.surface
    var padding: EdgeInsets = EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(containerColor)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ALIColors.outline, lineWidth: 1)
        )
    }
}

/// Title for each main screen (tab), with a touch of accent color
/// and an optional slot on the right (e.g. the add button).
struct ALITopBar<Trailing: View>: View {
    let title: LocalizedStringKey
    var accent: Color = ALIColors.primary
    @ViewBuilder var trailing: () -> Trailing

    init(title: LocalizedStringKey, accent: Color = ALIColors.primary, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.accent = accent
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(accent)
                .frame(width: 10, height: 10)
            Text(title)
                .font(ALITypography.headlineLarge)
                .foregroundStyle(ALIColors.ink)
            Spacer()
            trailing()
        }
        .frame(minHeight: 58)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

/// Primary button: solid pastel fill.
struct ALIPrimaryButton: View {
    let text: LocalizedStringKey
    var enabled: Bool = true
    var accent: Color = ALIColors.primary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(ALITypography.titleLarge)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 54)
        .foregroundStyle(ALIColors.onAccent.opacity(enabled ? 1 : 0.4))
        .background(enabled ? accent : ALIColors.outline)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .disabled(!enabled)
    }
}

/// Secondary button: soft outline.
struct ALISecondaryButton: View {
    let text: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(ALITypography.titleLarge)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 54)
        .foregroundStyle(ALIColors.ink)
        .background(ALIColors.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Text-only button, no background or border.
struct ALITextButton: View {
    let text: LocalizedStringKey
    var color: Color = ALIColors.mutedInk
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(ALITypography.labelLarge)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

/// Text field with a rounded border, consistent with the rest of the app.
struct ALITextField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        TextField(placeholder, text: $text)
            .submitLabel(.done)
            .onSubmit { onSubmit?() }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .foregroundStyle(ALIColors.ink)
            .background(ALIColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(ALIColors.outline, lineWidth: 1)
            )
    }
}

/// Password field matching `ALITextField`, with a show/hide toggle.
struct ALISecureField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var isNewPassword: Bool = false
    var onSubmit: (() -> Void)? = nil

    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textContentType(isNewPassword ? .newPassword : .password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit { onSubmit?() }

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ALIColors.mutedInk)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .foregroundStyle(ALIColors.ink)
        .background(ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ALIColors.outline, lineWidth: 1)
        )
    }
}

/// Round floating primary action button ("+").
struct ALIFloatingButton: View {
    var accent: Color = ALIColors.primary
    var systemImage: String = "plus"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ALIColors.onAccent)
                .frame(width: 58, height: 58)
                .background(accent)
                .clipShape(Circle())
                .shadow(color: accent.opacity(0.45), radius: 12, y: 6)
        }
    }
}

/// Friendly empty state, reusable across any tab.
struct ALIEmptyState: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 10) {
            ALIIconView(icon: icon, size: 42, color: ALIColors.mutedInk)
                .padding(.bottom, 4)
            Text(title)
                .font(ALITypography.titleLarge)
                .foregroundStyle(ALIColors.ink)
            Text(subtitle)
                .font(ALITypography.bodyMedium)
                .foregroundStyle(ALIColors.mutedInk)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 48)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }
}

/// "Are you sure you want to delete this?" dialog — same pattern across the app.
struct ALIDeleteConfirmDialog: ViewModifier {
    @Binding var isPresented: Bool
    let itemName: String
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.alert("Delete \"\(itemName)\"?", isPresented: $isPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onConfirm)
        } message: {
            Text("This action cannot be undone.")
        }
    }
}

extension View {
    func aliDeleteConfirmDialog(
        isPresented: Binding<Bool>,
        itemName: String,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(ALIDeleteConfirmDialog(isPresented: isPresented, itemName: itemName, onConfirm: onConfirm))
    }
}

/// Small crown badge overlaid (top-trailing) on a premium-gated
/// control, so it's visually obvious before tapping that it needs a
/// subscription.
struct ALIPremiumLockBadge: View {
    /// Same crown as `ALIPremiumPreviewBadge`: every premium marker in the
    /// app uses the crown, never a padlock.
    var body: some View { ALIPremiumPreviewBadge() }
}

/// Crown badge marking anything premium.
struct ALIPremiumPreviewBadge: View {
    var body: some View {
        Image(systemName: "crown.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(ALIColors.onAccent)
            .frame(width: 16, height: 16)
            .background(ALIColors.sun)
            .clipShape(Circle())
            .overlay(Circle().stroke(ALIColors.background, lineWidth: 1.5))
    }
}

extension View {
    /// Overlays `ALIPremiumPreviewBadge` in the top-trailing corner when `locked` is true.
    @ViewBuilder
    func aliPremiumPreviewOverlay(_ locked: Bool) -> some View {
        if locked {
            overlay(alignment: .topTrailing) { ALIPremiumPreviewBadge().offset(x: 4, y: -4) }
        } else {
            self
        }
    }

    /// Overlays `ALIPremiumLockBadge` in the top-trailing corner when `locked` is true.
    @ViewBuilder
    func aliPremiumLockOverlay(_ locked: Bool) -> some View {
        if locked {
            overlay(alignment: .topTrailing) { ALIPremiumLockBadge().offset(x: 4, y: -4) }
        } else {
            self
        }
    }
}

/// Banner shown over a premium screen opened as a preview: explains that
/// what's on screen is sample data and leads to the paywall.
struct ALIPremiumPreviewBanner: View {
    /// Which explanation to show; see `messageText`.
    var message: Message = .familyData
    let buttonTitle: LocalizedStringKey
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    enum Message {
        case familyData, tasksCalendar, peopleCalendar
    }

    /// Message with the "Aliaro" wordmark (salmon-dot "i") inlined.
    private var messageText: Text {
        let wordmark = Text(AliaroWordmark.inlineImage(size: 15, colorScheme: colorScheme))
            .baselineOffset(AliaroWordmark.inlineBaselineOffset(size: 15))
        switch message {
        case .familyData:
            return Text("This is a preview with sample data. Get \(wordmark) Premium to see your family's real data.")
        case .tasksCalendar:
            return Text("This is a preview with sample data. Get \(wordmark) Premium to see your tasks in a calendar.")
        case .peopleCalendar:
            return Text("This is a preview with sample data. Get \(wordmark) Premium to see your family's day by person.")
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ALIColors.onAccent)
                    .frame(width: 34, height: 34)
                    .background(ALIColors.sun)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Premium feature")
                        .font(ALITypography.titleLarge)
                        .foregroundStyle(ALIColors.ink)
                    messageText
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            ALIPrimaryButton(text: buttonTitle, action: action)
        }
        .padding(18)
        .background(ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ALIColors.outline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
    }
}

extension View {
    /// Premium preview: blurs the (sample) content and makes it
    /// non-interactive while `locked`. Pair with `ALIPremiumPreviewBanner`.
    func aliPremiumPreview(_ locked: Bool) -> some View {
        self
            .blur(radius: locked ? 3 : 0)
            .disabled(locked)
            .accessibilityHidden(locked)
    }

    /// Premium preview for a full screen: `aliPremiumPreview` on the
    /// content plus the banner pinned to the bottom.
    @ViewBuilder
    func aliPremiumPreviewBanner(_ locked: Bool, buttonTitle: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom) {
            if locked {
                ALIPremiumPreviewBanner(buttonTitle: buttonTitle, action: action)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Home

/// Summary card for the Home carousel: a feature's icon + name on top, the
/// headline fact of the day, and an optional supporting line. Tapping it
/// opens the feature (the action is handled by the caller's `Button`).
struct ALIHomeSummaryCard: View {
    let title: LocalizedStringKey
    let systemImage: String
    let accent: Color
    let headline: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ALIColors.onAccent)
                    .frame(width: 28, height: 28)
                    .background(accent)
                    .clipShape(Circle())
                Text(title)
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ALIColors.mutedInk)
            }

            Spacer(minLength: 0)

            Text(headline)
                .font(ALITypography.headlineMedium)
                .foregroundStyle(ALIColors.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)

            if let detail {
                Text(detail)
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [accent.opacity(0.28), ALIColors.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .background(ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ALIColors.outline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Square-ish shortcut tile for the Home feature grid: icon + name + a
/// short stat line ("12 recipes"). The stat line always takes its space so
/// every tile in the grid keeps the same height.
struct ALIFeatureTile: View {
    let title: LocalizedStringKey
    let systemImage: String
    let accent: Color
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ALIColors.onAccent)
                .frame(width: 44, height: 44)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ALITypography.titleLarge)
                    .foregroundStyle(ALIColors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail ?? " ")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ALIColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ALIColors.outline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Round avatar button used on the Home top bar to open People: the
/// first letter of the member's name, or a generic icon if there's no name.
struct ALIAvatarButton: View {
    let name: String?
    var accent: Color = ALIColors.peopleAccent
    let action: () -> Void

    private var initial: String? {
        guard let first = name?.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return String(first).uppercased()
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let initial {
                    Text(initial)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(ALIColors.onAccent)
                } else {
                    ALIIconView(icon: ALIIcon.user, size: 20, color: ALIColors.onAccent, fallback: ALIIcon.user)
                }
            }
                .frame(width: 44, height: 44)
                .background(accent.opacity(0.55))
                .clipShape(Circle())
                .overlay(Circle().stroke(ALIColors.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
