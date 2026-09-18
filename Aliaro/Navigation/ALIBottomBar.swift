import SwiftUI
import UIKit

/// Floating, rounded tab bar: Shopping, Tasks, Family — with a sliding
/// selection indicator that takes on each tab's pastel accent color.
///
/// `collapseFraction` (0...1) shrinks the bar in height and width at the
/// same time while the user scrolls down in any tab's content, and
/// expands it again when scrolling back up — see
/// `BottomBarScrollTracker` below.
struct ALIBottomBar: View {
    @Binding var selected: AppTab
    /// Tabs to show, in order — the admin's family-settings choices,
    /// already filtered (the Group tab is always included). Defaults to
    /// every tab so previews/tests don't need to pass one.
    var visibleTabs: [AppTab] = AppTab.allCases
    var collapseFraction: CGFloat = 0

    private let expandedHeight: CGFloat = 56
    private let collapsedHeight: CGFloat = 46
    private let expandedWidthFraction: CGFloat = 0.96
    private let collapsedWidthFraction: CGFloat = 0.8
    private let barCornerRadius: CGFloat = 28
    private let indicatorInset: CGFloat = 4
    private let indicatorVerticalInset: CGFloat = 6

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
                        .frame(width: slotWidth - indicatorInset * 2, height: barHeight - indicatorVerticalInset * 2)
                        .offset(x: selectedIndex * slotWidth + indicatorInset)

                    HStack(spacing: 0) {
                        ForEach(visibleTabs) { tab in
                            Button {
                                selected = tab
                            } label: {
                                Image(systemName: tab.systemImage)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(tab == selected ? ALIColors.ink : ALIColors.mutedInk)
                                    .frame(width: slotWidth, height: barHeight)
                            }
                            .disabled(tab == selected)
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

                Spacer(minLength: 0)
            }
        }
        .frame(height: expandedHeight)
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .ignoresSafeArea(.container, edges: .bottom)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selected)
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
    private var lastOffset: CGFloat?

    /// `offset` is the distance (in points, positive downward) scrolled
    /// from rest. Clamped to `>= 0` to ignore the native bounce.
    func update(offset: CGFloat) {
        let clampedOffset = max(0, offset)
        defer { lastOffset = clampedOffset }
        guard let last = lastOffset else { return }
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
        lastOffset = nil
        guard collapseFraction != 0 else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            collapseFraction = 0
        }
    }
}

/// Finds the actual `UIScrollView` that contains this view and observes its
/// `contentOffset` via KVO — without touching its `delegate`.
private struct ScrollOffsetReader: UIViewRepresentable {
    let onChange: (CGFloat) -> Void

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
        var onChange: (CGFloat) -> Void
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?

        init(onChange: @escaping (CGFloat) -> Void) {
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
                DispatchQueue.main.async {
                    self?.onChange(offset)
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
            ScrollOffsetReader { offset in
                tracker.update(offset: offset)
            }
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
