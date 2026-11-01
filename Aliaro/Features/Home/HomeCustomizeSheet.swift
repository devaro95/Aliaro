import SwiftUI

/// "Customize Home": drag the blocks (Today, Board, All features) and the
/// "Today" cards into the order you want, and switch off what you don't
/// want to see. Only for this member, on this device.
struct HomeCustomizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var familySession: FamilySession
    @ObservedObject private var layout = HomeLayout.shared

    /// Visible features in this member's grid order (from Home).
    let visibleFeatures: [AppTab]

    @State private var showReset = false

    /// Blocks that apply to this group (the Board only if the admin didn't hide it).
    private var blocks: [HomeBlock] {
        layout.orderedBlocks.filter { $0 != .board || visibleFeatures.contains(.board) }
    }

    private var todayTabs: [AppTab] { layout.orderedTodayTabs(featureOrder: visibleFeatures) }

    var body: some View {
        trackedBody.trackScreen("home_customize")
    }

    @ViewBuilder
    private var trackedBody: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Features", selection: Binding(
                        get: { layout.featureStyle },
                        set: { style in
                            withAnimation { layout.setFeatureStyle(style) }
                            Track.event("home_feature_style", ["style": style.rawValue])
                        }
                    )) {
                        ForEach(HomeFeatureStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    HomeFeatureStylePreview(style: layout.featureStyle, tabs: visibleFeatures)
                        .listRowBackground(ALIColors.surface)
                } header: {
                    Text("All features")
                } footer: {
                    Text(layout.featureStyle == .cards
                         ? "Big cards with a summary of each feature."
                         : "Just the icons with their name: many more fit in each row.")
                }

                Section {
                    ForEach(blocks) { block in
                        blockRow(block)
                    }
                    .onMove { from, to in
                        var order = blocks
                        order.move(fromOffsets: from, toOffset: to)
                        // Keep blocks not shown here (e.g. a hidden Board) after the rest.
                        layout.setBlockOrder(order + layout.orderedBlocks.filter { !order.contains($0) })
                        Track.event("home_blocks_reorder", ["order": order.map(\.rawValue).joined(separator: ",")])
                    }
                } header: {
                    Text("Sections")
                } footer: {
                    Text("Drag to change the order. \"All features\" is always shown: it's how you reach everything.")
                }

                if !todayTabs.isEmpty && !layout.isHidden(.today) {
                    Section {
                        ForEach(todayTabs) { tab in
                            todayRow(tab)
                        }
                        .onMove { from, to in
                            var order = todayTabs
                            order.move(fromOffsets: from, toOffset: to)
                            layout.setTodayOrder(order)
                            Track.event("home_today_reorder")
                        }
                    } header: {
                        Text("Today cards")
                    } footer: {
                        Text("A card only shows up when there's something for today.")
                    }
                }

                if layout.isCustomized || !familySession.homeFeatureOrder.isEmpty {
                    Section {
                        Button("Reset Home", role: .destructive) { showReset = true }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(ALIColors.background)
            .navigationTitle("Customize Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Reset Home?", isPresented: $showReset) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    withAnimation {
                        layout.reset()
                        familySession.setHomeFeatureOrder([])
                    }
                    Track.event("home_layout_reset")
                }
            } message: {
                Text("Sections, cards and features will go back to their original order and everything will show again. This only changes it for you.")
            }
        }
        .presentationDetents([.large])
    }

    private func blockRow(_ block: HomeBlock) -> some View {
        HStack(spacing: 12) {
            icon(block.systemImage, color: block.accent)
            Text(block.label)
                .font(ALITypography.bodyLarge)
                .foregroundStyle(ALIColors.ink)
            Spacer()
            if block.canHide {
                Toggle("", isOn: Binding(
                    get: { !layout.isHidden(block) },
                    set: { shown in
                        withAnimation { layout.setHidden(block, !shown) }
                        Track.event("home_block_toggle", ["block": block.rawValue, "shown": shown])
                    }
                ))
                .labelsHidden()
                .tint(ALIColors.primary)
            } else {
                Text("Always")
                    .font(ALITypography.labelLarge)
                    .foregroundStyle(ALIColors.mutedInk)
            }
        }
        .listRowBackground(ALIColors.surface)
    }

    private func todayRow(_ tab: AppTab) -> some View {
        HStack(spacing: 12) {
            icon(tab.systemImage, color: tab.accent)
            Text(tab.label)
                .font(ALITypography.bodyLarge)
                .foregroundStyle(ALIColors.ink)
            Spacer()
            Toggle("", isOn: Binding(
                get: { !layout.isHidden(todayCard: tab) },
                set: { shown in
                    withAnimation { layout.setHidden(todayCard: tab, !shown) }
                    Track.event("home_today_card_toggle", ["tab": tab.settingsKey, "shown": shown])
                }
            ))
            .labelsHidden()
            .tint(ALIColors.primary)
        }
        .listRowBackground(ALIColors.surface)
    }

    private func icon(_ systemImage: String, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(ALIColors.onAccent)
            .frame(width: 30, height: 30)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Small live sketch of the features grid in the chosen style, so the
/// change is visible without closing the sheet.
private struct HomeFeatureStylePreview: View {
    let style: HomeFeatureStyle
    let tabs: [AppTab]

    var body: some View {
        Group {
            if style == .icons {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 10) {
                    ForEach(Array(tabs.prefix(8))) { tab in
                        VStack(spacing: 4) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ALIColors.onAccent)
                                .frame(width: 34, height: 34)
                                .background(tab.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(tab.label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(ALIColors.ink)
                                .lineLimit(1)
                        }
                    }
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(Array(tabs.prefix(4))) { tab in
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(ALIColors.onAccent)
                                .frame(width: 24, height: 24)
                                .background(tab.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            Text(tab.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(ALIColors.ink)
                                .lineLimit(1)
                            Capsule()
                                .fill(ALIColors.mutedInk.opacity(0.25))
                                .frame(width: 44, height: 5)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ALIColors.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ALIColors.outline, lineWidth: 1))
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: style)
        .accessibilityHidden(true)
    }
}
