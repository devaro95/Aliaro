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

/// Round floating primary action button ("+").
struct ALIFloatingButton: View {
    var accent: Color = ALIColors.primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
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
    let emoji: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 10) {
            Text(emoji)
                .font(.system(size: 44))
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

/// Small padlock badge overlaid (top-trailing) on a premium-gated
/// control, so it's visually obvious before tapping that it needs a
/// subscription.
struct ALIPremiumLockBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(ALIColors.onAccent)
            .frame(width: 16, height: 16)
            .background(ALIColors.sun)
            .clipShape(Circle())
            .overlay(Circle().stroke(ALIColors.background, lineWidth: 1.5))
    }
}

extension View {
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
