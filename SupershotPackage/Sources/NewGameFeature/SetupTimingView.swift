import AppSettings
import AppUI
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
import SubscriptionClient
import SwiftUI
import TeamEditingFeature
import UI

package struct SetupTimingView: View {
  @Bindable package var store: StoreOf<SetupTimingFeature>

  package var body: some View {
    List {
      Section {
        Picker("Periods", selection: Binding(
          get: { store.timing.periodCount },
          set: { store.send(.periodCountChanged($0)) }
        )) {
          ForEach(GamePeriodFormat.editableCounts, id: \.self) { count in
            Text(count == 4 ? "4 (quarters)" : "\(count)").tag(count)
          }
        }
        SetupDurationRow(
          title: "\(store.timing.periodTitle) length",
          duration: store.timing.periodDuration
        ) {
          store.send(.editDurationButtonTapped(.quarter))
        }
      } footer: {
        Text(store.timing.summary)
      }

      if store.timing.breakCount > 0 {
        Section {
          if store.timing.customizesBreaks {
            ForEach(store.timing.individualBreakDurations.indices, id: \.self) { index in
              SetupDurationRow(
                title: LocalizedStringKey(store.timing.breakTitle(at: index)),
                duration: store.timing.individualBreakDurations[index]
              ) {
                store.send(.editDurationButtonTapped(.individualBreak(index)))
              }
            }

            Button("Use first break for all") {
              store.send(.useFirstBreakForAllButtonTapped)
            }
            .buttonStyle(.borderless)
          } else {
            SetupDurationRow(title: "Break length", duration: store.timing.sharedBreakDuration) {
              store.send(.editDurationButtonTapped(.allBreaks))
            }

            Button("Customize each break") {
              store.send(.customizeBreaksButtonTapped)
            }
            .buttonStyle(.borderless)
          }
          Toggle("Auto start breaks", isOn: $store.timing.breakStartPolicy.isAutomatic)
        } header: {
          Text("Breaks")
        } footer: {
          Text(store.timing.breakStartPolicy == .automatic
            ? "Breaks start when a \(store.timing.periodTitle.lowercased()) ends."
            : "Breaks wait for you to tap Start break.")
        }
      }

      if !store.timing.isValid {
        Section {
          Label("Enter valid period and break durations.", systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
        }
      }
    }
    #if os(iOS)
    .listStyle(.insetGrouped)
    #else
    .listStyle(.inset)
    #endif
    .scrollContentBackground(.hidden)
    .background(Color.setupBackground.ignoresSafeArea())
  }

  package init(store: StoreOf<SetupTimingFeature>) {
    self.store = store
  }
}

private struct SetupDurationRow: View {
  let title: LocalizedStringKey
  let duration: NewGameFeature.DurationDraft
  var edit: () -> Void

  var body: some View {
    Button(action: edit) {
      HStack {
        Text(title)
          .foregroundStyle(.primary)
        Spacer()
        Text(duration.formatted)
          .monospacedDigit()
          .foregroundStyle(.secondary)
        Image(systemName: "chevron.right")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
    .accessibilityValue(duration.formatted)
    .accessibilityHint("Edit duration")
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
