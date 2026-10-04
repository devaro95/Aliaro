import SwiftUI
import UIKit

/// Floating, rounded tab bar: Home + the group's (up to 5) favorite
/// features — with a sliding selection indicator that takes on each
/// tab's pastel accent color.
///
/// `collapseFraction` (0...1) shrinks the bar in height and width at the
/// same time while the user scrolls down in any tab's content, and
/// expands it again when scrolling back up — see
/// `BottomBarScrollTracker` below.
struct ALIBottomBar: View {
    @Binding var selected: AppTab
    /// Tabs to show, in order — Home followed by the admin's favorites,
    /// already filtered. Defaults to Home + the first 3 features so
    /// previews/tests don't need to pass one.
    var visibleTabs: [AppTab] = [.home] + AppTab.features.prefix(AppTab.defaultFavoritesCount)
    var collapseFraction: CGFloat = 0
    /// Called when the already-selected tab is tapped again (e.g. Home
    /// pops back to its root).
    var onReselect: ((AppTab) -> Void)? = nil

    private let expandedHeight: CGFloat = 56
    private let collapsedHeight: CGFloat = 46
    private let expandedWidthFraction: CGFloat = 0.96
    private let collapsedWidthFraction: CGFloat = 0.8
    private let barCornerRadius: CGFloat = 28
    private let indicatorInset: CGFloat = 4
    private let indicatorVerticalInset: CGFloat = 4

    /// Entrance animation plays once per process: a cold launch (app killed
    /// and reopened) shows it; tab switches, re-mounts or coming back from
    /// background don't, because the process — and this flag — survive.
    @MainActor private static var hasPlayedEntrance = false
    @State private var barVisible = ALIBottomBar.hasPlayedEntrance
    @State private var iconsVisible = ALIBottomBar.hasPlayedEntrance

    var body: some View {
        GeometryReader { outerGeo in
            let barHeight = expandedHeight - (expandedHeight - collapsedHeight) * collapseFraction
            let widthFraction = expandedWidthFraction - (expandedWidthFraction - collapsedWidthFraction) * collapseFraction
            let barWidth = outerGeo.size.width * widthFraction
            let slotWidth = barWidth / CGFloat(visibleTabs.count)
            let selectedIndex = CGFloat(visibleTabs.firstIndex(of: selected) ?? 0)

            HStack(spacing: 0) {
                Spacer(minLength: 0)

                ZStack(alignment: .leading) {
                    // Pastel background that slides instead of being redrawn per tab.
                    // Same cornerRadius as the outer bar (barCornerRadius) so it nests well.
                    RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                        .fill(selected.accent.opacity(0.55))
                        .opacity(iconsVisible ? 1 : 0)
                        .animation(.easeOut(duration: 0.3).delay(0.1), value: iconsVisible)
                        .frame(width: slotWidth - indicatorInset * 2, height: barHeight - indicatorVerticalInset * 2)
                        .offset(x: selectedIndex * slotWidth + indicatorInset)

                    HStack(spacing: 0) {
                        ForEach(visibleTabs) { tab in
                            Button {
                                if tab == selected {
                                    onReselect?(tab)
                                } else {
                                    selected = tab
                                }
                            } label: {
                                let index = Double(visibleTabs.firstIndex(of: tab) ?? 0)
                                Image(systemName: tab.systemImage)
                                    .font(.system(size: visibleTabs.count > 4 ? 18 : 20, weight: .semibold))
                                    .foregroundStyle(tab == selected ? ALIColors.ink : ALIColors.mutedInk)
                                    .scaleEffect(iconsVisible ? 1 : 0.4)
                                    .opacity(iconsVisible ? 1 : 0)
                                    .animation(
                                        .spring(response: 0.45, dampingFraction: 0.6).delay(0.05 * index),
                                        value: iconsVisible
                                    )
                                    .frame(width: slotWidth, height: barHeight)
                            }
                            .accessibilityLabel(tab.label)
                        }
                    }
                }
                .frame(width: barWidth, height: barHeight)
                .background(ALIColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                        .stroke(ALIColors.outline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
                .scaleEffect(barVisible ? 1 : 0.85, anchor: .bottom)
                .offset(y: barVisible ? 0 : 100)
                .opacity(barVisible ? 1 : 0)

                Spacer(minLength: 0)
            }
        }
        .frame(height: expandedHeight)
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .ignoresSafeArea(.container, edges: .bottom)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selected)
        .onAppear(perform: playEntranceIfNeeded)
    }

    private func playEntranceIfNeeded() {
        guard !Self.hasPlayedEntrance else { return }
        Self.hasPlayedEntrance = true
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.15)) {
            barVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            iconsVisible = true
        }
    }
}

/// Converts any tab's scroll into the 0...1 signal that shrinks/expands
/// `ALIBottomBar`. A single shared tracker (injected as an
/// `@EnvironmentObject` from `MainTabContainer`) that each screen reports
/// its real UIKit offset to with `.trackBottomBarScroll(_:)`.
@MainActor
final class BottomBarScrollTracker: ObservableObject {
    @Published private(set) var collapseFraction: CGFloat = 0

    private let threshold: CGFloat = 120
    /// Last offset seen per scroll view. Several can report at once (Home
    /// stays mounted, scrolled, under a pushed feature), so each one keeps
    /// its own baseline — mixing them turned Home's offset into a fake
    /// "scroll down" on the pushed screen.
    private var lastOffsets: [ObjectIdentifier: CGFloat] = [:]

    /// `offset` is the distance (in points, positive downward) scrolled
    /// from rest. Clamped to `>= 0` to ignore the native bounce.
    ///
    /// `userDriven` is whether the finger is (or just was) moving the
    /// scroll view. Offset changes that aren't — a push/pop adjusting the
    /// content insets, layout changes, a screen that's still mounted
    /// behind another one — only move the baseline, so the bar never
    /// shrinks when nobody scrolled. Back at the top it always expands.
    func update(offset: CGFloat, userDriven: Bool, source: ObjectIdentifier) {
        let clampedOffset = max(0, offset)
        let lastOffset = lastOffsets[source]
        defer { lastOffsets[source] = clampedOffset }
        if clampedOffset == 0, collapseFraction != 0 {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                collapseFraction = 0
            }
            return
        }
        guard userDriven, let last = lastOffset else { return }
        let delta = clampedOffset - last
        guard delta != 0 else { return }
        let newProgress = (collapseFraction * threshold + delta).clamped(to: 0...threshold)
        let target = newProgress / threshold
        guard target != collapseFraction else { return }
        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.86, blendDuration: 0.1)) {
            collapseFraction = target
        }
    }

    /// Called when switching tabs, so a bar collapsed on the previous
    /// screen doesn't stay shrunk when entering one without scroll.
    func reset() {
        lastOffsets.removeAll()
        guard collapseFraction != 0 else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            collapseFraction = 0
        }
    }
}

/// Finds the actual `UIScrollView` that contains this view and observes its
/// `contentOffset` via KVO — without touching its `delegate`.
private struct ScrollOffsetReader: UIViewRepresentable {
    let onChange: (CGFloat, Bool, ObjectIdentifier) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.attachIfNeeded(from: uiView)
    }

    final class Coordinator {
        var onChange: (CGFloat, Bool, ObjectIdentifier) -> Void
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?

        init(onChange: @escaping (CGFloat, Bool, ObjectIdentifier) -> Void) {
            self.onChange = onChange
        }

        func attachIfNeeded(from view: UIView) {
            guard scrollView == nil else { return }
            var candidate = view.superview
            while let current = candidate, !(current is UIScrollView) {
                candidate = current.superview
            }
            guard let found = candidate as? UIScrollView else { return }
            scrollView = found
            observation = found.observe(\.contentOffset, options: [.new, .initial]) { [weak self] scrollView, _ in
                let insets = scrollView.adjustedContentInset
                let maxScrollableOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height + insets.bottom + insets.top)
                let rawOffset = scrollView.contentOffset.y + insets.top
                let offset = rawOffset.clamped(to: 0...maxScrollableOffset)
                // Only a visible scroll view moved by the user counts (see
                // `BottomBarScrollTracker.update`).
                let userDriven = scrollView.window != nil
                    && (scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating)
                let source = ObjectIdentifier(scrollView)
                DispatchQueue.main.async {
                    self?.onChange(offset, userDriven, source)
                }
            }
        }
    }
}

extension View {
    /// Placed once, as the first thing inside a `ScrollView`'s content
    /// (zero height, doesn't affect layout): reports that `ScrollView`'s
    /// real scroll to the shared tracker so `ALIBottomBar` can
    /// shrink/expand.
    func trackBottomBarScroll(_ tracker: BottomBarScrollTracker) -> some View {
        background(
            ScrollOffsetReader { offset, userDriven, source in
                tracker.update(offset: offset, userDriven: userDriven, source: source)
            }
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
