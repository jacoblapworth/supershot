import ComposableArchitecture
import SwiftUI

struct SetupTimingView: View {
  @Bindable var store: StoreOf<NewGameFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("Timing", systemImage: "timer")
        .font(.headline)

      DurationEditor(
        duration: $store.periodDuration,
        label: "Quarter length",
        presets: [6, 10, 12, 15, 20].map { $0 * 60 },
        presetTapped: { store.send(.periodPresetButtonTapped($0)) }
      )

      Divider()

      if store.customizesBreaks {
        DurationEditor(
          duration: $store.firstBreakDuration,
          label: "After quarter 1",
          presets: [0, 1, 2, 4, 5].map { $0 * 60 },
          presetTapped: { store.send(.firstBreakPresetButtonTapped($0)) }
        )
        DurationEditor(
          duration: $store.halfTimeDuration,
          label: "Half time",
          presets: [0, 1, 2, 4, 5, 8, 10, 12].map { $0 * 60 },
          presetTapped: { store.send(.halfTimePresetButtonTapped($0)) }
        )
        DurationEditor(
          duration: $store.secondBreakDuration,
          label: "After quarter 3",
          presets: [0, 1, 2, 4, 5].map { $0 * 60 },
          presetTapped: { store.send(.secondBreakPresetButtonTapped($0)) }
        )

        Button("Use first break for all") {
          store.send(.useFirstBreakForAllButtonTapped)
        }
        .buttonStyle(.bordered)
      } else {
        DurationEditor(
          duration: $store.firstBreakDuration,
          label: "All breaks",
          presets: [0, 1, 2, 4, 5].map { $0 * 60 },
          presetTapped: { store.send(.allBreakPresetButtonTapped($0)) }
        )

        Button("Customize each break") {
          store.send(.customizeBreaksButtonTapped)
        }
        .buttonStyle(.bordered)
      }
    }
    .setupCardStyle()
  }
}

private struct DurationEditor: View {
  @Binding var duration: NewGameFeature.DurationDraft
  var label: String
  var presets: [Int]
  var presetTapped: (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(label)
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text(duration.formatted)
          .font(.subheadline.monospacedDigit().weight(.semibold))
          .foregroundStyle(duration.totalSeconds == nil ? Color.red : Color.secondary)
      }

      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(presets, id: \.self) { seconds in
            Button {
              presetTapped(seconds)
            } label: {
              if duration.totalSeconds == seconds {
                Label(formatted(seconds), systemImage: "checkmark")
              } else {
                Text(formatted(seconds))
              }
            }
            .buttonStyle(.bordered)
          }
        }
      }
      .scrollIndicators(.hidden)

      HStack(spacing: 8) {
        TextField("Minutes", text: $duration.minutesText)
          .textFieldStyle(.roundedBorder)
        Text("min")
          .foregroundStyle(.secondary)
        TextField("Seconds", text: $duration.secondsText)
          .textFieldStyle(.roundedBorder)
        Text("sec")
          .foregroundStyle(.secondary)
      }
      .font(.subheadline)
    }
  }

  private func formatted(_ seconds: Int) -> String {
    "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
  }
}

#Preview("Uniform breaks") {
  SetupTimingView(store: setupPreviewStore())
    .padding()
}

#Preview("Custom breaks") {
  SetupTimingView(store: setupPreviewStore(.previewCustomTiming))
    .padding()
}

#Preview("Invalid duration") {
  SetupTimingView(store: setupPreviewStore(.previewInvalidTiming))
    .padding()
}
