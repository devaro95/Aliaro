import SwiftUI

/// Push alerts before a task or calendar event: up to 2, chosen from fixed
/// times. Each value is the number of seconds BEFORE the moment (0 = at the
/// time). For all-day events the moment is 09:00 of that day.
///
/// Stored as `alert_offsets` (int[]) in Supabase; nil = default alerts
/// (`ALIAlerts.defaultOffsets`), [] = no alerts. Sent by
/// `dispatch-family-notifications` to the people it's for.
enum ALIAlerts {
    static let maxCount = 2

    static let timedOptions = [0, 300, 600, 900, 1800, 3600, 7200, 86_400]
    static let allDayOptions = [0, 86_400, 172_800, 604_800]

    /// What the backend does when nothing was chosen (same as before alerts
    /// existed): events 1 h before (all-day: 09:00 that day), tasks at the time.
    static func defaultOffsets(isEvent: Bool, isAllDay: Bool) -> [Int] {
        isEvent && !isAllDay ? [3600] : [0]
    }

    static func label(_ seconds: Int, isAllDay: Bool) -> String {
        switch seconds {
        case 0: return isAllDay ? String(localized: "On the day (9:00)") : String(localized: "At the time")
        case 300: return String(localized: "5 minutes before")
        case 600: return String(localized: "10 minutes before")
        case 900: return String(localized: "15 minutes before")
        case 1800: return String(localized: "30 minutes before")
        case 3600: return String(localized: "1 hour before")
        case 7200: return String(localized: "2 hours before")
        case 86_400: return String(localized: "1 day before")
        case 172_800: return String(localized: "2 days before")
        case 604_800: return String(localized: "1 week before")
        default:
            let minutes = seconds / 60
            return minutes >= 60
                ? String(localized: "\(minutes / 60) h before")
                : String(localized: "\(minutes) min before")
        }
    }

    /// Short summary for detail screens: "15 minutes before · 1 day before".
    static func summary(_ offsets: [Int], isAllDay: Bool) -> String {
        offsets.isEmpty
            ? String(localized: "No alerts")
            : offsets.sorted().map { label($0, isAllDay: isAllDay) }.joined(separator: " · ")
    }
}

struct ALIAlertsCard: View {
    @Binding var offsets: [Int]
    var isAllDay: Bool = false
    var accent: Color = ALIColors.primary
    var enabled: Bool = true

    private var options: [Int] { isAllDay ? ALIAlerts.allDayOptions : ALIAlerts.timedOptions }

    var body: some View {
        ALICard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(accent)
                    Text("Alerts")
                        .font(ALITypography.labelLarge)
                        .foregroundStyle(ALIColors.mutedInk)
                }

                if offsets.isEmpty {
                    Text("No alerts")
                        .font(ALITypography.bodyMedium)
                        .foregroundStyle(ALIColors.mutedInk)
                }

                ForEach(Array(offsets.enumerated()), id: \.offset) { index, value in
                    HStack(spacing: 10) {
                        Menu {
                            ForEach(options.filter { $0 == value || !offsets.contains($0) }, id: \.self) { option in
                                Button {
                                    offsets[index] = option
                                } label: {
                                    if option == value {
                                        Label(ALIAlerts.label(option, isAllDay: isAllDay), systemImage: "checkmark")
                                    } else {
                                        Text(ALIAlerts.label(option, isAllDay: isAllDay))
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(ALIAlerts.label(value, isAllDay: isAllDay))
                                    .font(ALITypography.bodyLarge)
                                    .foregroundStyle(ALIColors.ink)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(ALIColors.mutedInk)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(ALIColors.surfaceVariant)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .disabled(!enabled)

                        Button {
                            withAnimation { _ = offsets.remove(at: index) }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(ALIColors.mutedInk)
                        }
                        .buttonStyle(.plain)
                        .disabled(!enabled)
                        .accessibilityLabel(Text("Remove alert"))
                    }
                }

                if enabled && offsets.count < ALIAlerts.maxCount,
                   let next = options.first(where: { !offsets.contains($0) }) {
                    Button {
                        withAnimation { offsets.append(next) }
                    } label: {
                        Label("Add alert", systemImage: "plus.circle.fill")
                            .font(ALITypography.bodyLarge)
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                }

                Text("Up to 2. Only the people it's for get them.")
                    .font(ALITypography.bodyMedium)
                    .foregroundStyle(ALIColors.mutedInk)
            }
        }
    }
}
