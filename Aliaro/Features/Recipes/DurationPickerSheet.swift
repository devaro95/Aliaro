import SwiftUI

/// Hours + minutes wheels to set a duration quickly, with shortcuts for
/// the most common times. 0 means "not set".
struct DurationPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: LocalizedStringKey
    @Binding var minutes: Int

    @State private var hours = 0
    @State private var mins = 0

    private static let minuteSteps = Array(stride(from: 0, through: 55, by: 5))
    private static let presets = [10, 15, 20, 30, 45, 60, 90]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.presets, id: \.self) { preset in
                            RecipeChip(title: "\(RecipeFormatting.duration(preset))", isSelected: hours * 60 + mins == preset) {
                                hours = preset / 60
                                mins = preset % 60
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                HStack(spacing: 0) {
                    Picker("Hours", selection: $hours) {
                        ForEach(0...12, id: \.self) { value in
                            Text("\(value) h").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)

                    Picker("Minutes", selection: $mins) {
                        ForEach(Self.minuteSteps, id: \.self) { value in
                            Text("\(value) min").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(height: 160)
                .padding(.horizontal, 20)

                HStack(spacing: 12) {
                    ALISecondaryButton(text: "Clear") {
                        minutes = 0
                        dismiss()
                    }
                    ALIPrimaryButton(text: "Done", accent: ALIColors.recipesAccent) {
                        minutes = hours * 60 + mins
                        dismiss()
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 8)
            .background(ALIColors.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(380)])
        .onAppear {
            hours = min(minutes / 60, 12)
            // Round to the wheel's 5-minute steps.
            mins = min((minutes % 60 + 2) / 5 * 5, 55)
        }
    }
}
