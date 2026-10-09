import ComposableArchitecture
import SwiftUI

struct SetupTimingView: View {
  @Bindable var store: StoreOf<SetupTimingFeature>
  
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("Timing", systemImage: "timer")
        .font(.headline)

      durationRow("Quarters",
        duration:store.timing.periodDuration, field:.quarter
      )
      
      Divider()
      
      if store.timing.customizesBreaks {
        durationRow(
          "After quarter 1",
          duration:store.timing.firstBreakDuration, field: .firstBreak)
        durationRow("Half time",
          duration:store.timing.halfTimeDuration, field: .halfTime)
        durationRow(
          "After quarter 3",
          duration:store.timing.secondBreakDuration, field:.secondBreak
        )
        
        Button("Use first break for all") {
          store.send(.useFirstBreakForAllButtonTapped)
        }
        .buttonStyle(.bordered)
      } else {
        durationRow("Breaks",
          duration:store.timing.firstBreakDuration, field:.allBreaks
        )
        
        Button("Customize each break") {
          store.send(.customizeBreaksButtonTapped)
        }
        .buttonStyle(.bordered)
      }
    }
    .setupCardStyle()
  }

private func durationRow(
    _ label: String, duration: NewGameFeature.DurationDraft, field: SetupTimingFeature.DurationField) -> some View {
      HStack {
        Text(label)
        Spacer()
        Text(duration.formatted)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      Button("Edit") { store.send(.editDurationButtonTapped(field)) }
          .accessibilityLabel("Edit \(label)")
      }
  }
}

#Preview("Uniform breaks") {
  SetupTimingEditorView(store: Store(initialState: SetupTimingFeature.State(timing: SetupTiming())) {
    SetupTimingFeature()
  })
}

#Preview("Custom breaks") {
  SetupTimingEditorView(store: Store(initialState: SetupTimingFeature.State(timing: NewGameFeature.State.previewCustomTiming.timing)) {
    SetupTimingFeature()
  })
}

#Preview("Invalid duration") {
  SetupTimingEditorView(store: Store(initialState: SetupTimingFeature.State(timing: NewGameFeature.State.previewInvalidTiming.timing)) {
    SetupTimingFeature()
  })
}
