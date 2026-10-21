import AppSettings
import ComposableArchitecture
import Database
import GameAnalysis
import GameCore
import GameServices
import LocationClient
import PermissionsFeature
import PreviewSupport
import ScoringFeature
import SharedModels
import Styleguide
import SubscriptionClient
import SwiftUI
import TeamEditingFeature
import WidgetSupport

package struct SetupTimingView: View {
  @Bindable package var store: StoreOf<SetupTimingFeature>

  package var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("Timing", systemImage: "timer")
        .font(.headline)

      durationRow(
        "Quarters",
        duration: store.timing.periodDuration, field: .quarter
      )

      HStack {
        Text("Start breaks")
        Spacer()
        Picker("Start breaks", selection: $store.timing.breakStartPolicy) {
          Text("Automatically").tag(BreakStartPolicy.automatic)
          Text("Manually").tag(BreakStartPolicy.manual)
        }
        .labelsHidden()
      }
      Text(
        store.timing.breakStartPolicy == .automatic
          ? "Breaks start when a quarter ends."
          : "Breaks wait for you to tap Start break."
      )
      .font(.subheadline).foregroundStyle(.secondary)

      Divider()

      if store.timing.customizesBreaks {
        durationRow(
          "After quarter 1",
          duration: store.timing.firstBreakDuration, field: .firstBreak
        )
        durationRow(
          "Half time",
          duration: store.timing.halfTimeDuration, field: .halfTime
        )
        durationRow(
          "After quarter 3",
          duration: store.timing.secondBreakDuration, field: .secondBreak
        )

        Button("Use first break for all") {
          store.send(.useFirstBreakForAllButtonTapped)
        }
        .buttonStyle(.bordered)
      } else {
        durationRow(
          "Breaks",
          duration: store.timing.firstBreakDuration, field: .allBreaks
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
    _ label: String, duration: NewGameFeature.DurationDraft, field: SetupTimingFeature.DurationField
  ) -> some View {
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

  package init(store: StoreOf<SetupTimingFeature>) {
    self.store = store
  }
}

#Preview("Uniform breaks") {
  SetupTimingEditorView(
    store: Store(initialState: SetupTimingFeature.State(timing: SetupTiming())) {
      SetupTimingFeature()
    }
  )
}

#Preview("Custom breaks") {
  SetupTimingEditorView(
    store: Store(
      initialState: SetupTimingFeature.State(
        timing: NewGameFeature.State.previewCustomTiming.timing
      )
    ) {
      SetupTimingFeature()
    }
  )
}

#Preview("Invalid duration") {
  SetupTimingEditorView(
    store: Store(
      initialState: SetupTimingFeature.State(
        timing: NewGameFeature.State.previewInvalidTiming.timing
      )
    ) {
      SetupTimingFeature()
    }
  )
}
