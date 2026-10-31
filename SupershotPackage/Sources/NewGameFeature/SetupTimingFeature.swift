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

package nonisolated struct SetupTiming: Equatable, Sendable {
  package var breakStartPolicy = BreakStartPolicy.automatic
  package var customizesBreaks = false
  package var firstBreakDuration = NewGameFeature.DurationDraft(totalSeconds: 60)
  package var halfTimeDuration = NewGameFeature.DurationDraft(totalSeconds: 60)
  package var periodDuration = NewGameFeature.DurationDraft(totalSeconds: 480)
  package var secondBreakDuration = NewGameFeature.DurationDraft(totalSeconds: 60)

  package var isValid: Bool {
    (periodDuration.totalSeconds ?? 0) > 0
      && firstBreakDuration.totalSeconds != nil
      && halfTimeDuration.totalSeconds != nil
      && secondBreakDuration.totalSeconds != nil
  }

  package var summary: String {
    let breaks = [firstBreakDuration, halfTimeDuration, secondBreakDuration].map(\.formatted)
    if Set(breaks).count == 1 {
      return "4 × \(periodDuration.formatted) · \(breaks[0]) breaks"
    }
    return
      "4 × \(periodDuration.formatted) · Q1 break \(breaks[0]) · Half time \(breaks[1]) · Q3 break \(breaks[2])"
  }

  package init(
    breakStartPolicy: BreakStartPolicy = BreakStartPolicy.automatic,
    customizesBreaks: Bool = false,
    firstBreakDuration: NewGameFeature.DurationDraft = NewGameFeature.DurationDraft(totalSeconds: 60),
    halfTimeDuration: NewGameFeature.DurationDraft = NewGameFeature.DurationDraft(totalSeconds: 60),
    periodDuration: NewGameFeature.DurationDraft = NewGameFeature.DurationDraft(totalSeconds: 480),
    secondBreakDuration: NewGameFeature.DurationDraft = NewGameFeature.DurationDraft(totalSeconds: 60)
  ) {
    self.breakStartPolicy = breakStartPolicy
    self.customizesBreaks = customizesBreaks
    self.firstBreakDuration = firstBreakDuration
    self.halfTimeDuration = halfTimeDuration
    self.periodDuration = periodDuration
    self.secondBreakDuration = secondBreakDuration
  }
}

@Reducer
package struct SetupTimingFeature {
  @ObservableState
  package struct State: Equatable {
    @Presents package var timeInput: TimeInputFeature.State?
    package var editedDuration: DurationField?
    package var timing: SetupTiming

    package init(
      timeInput: TimeInputFeature.State? = nil,
      editedDuration: DurationField? = nil,
      timing: SetupTiming
    ) {
      self.timeInput = timeInput
      self.editedDuration = editedDuration
      self.timing = timing
    }
  }

  package enum DurationField: Equatable {
    case quarter, allBreaks, firstBreak, halfTime, secondBreak
  }

  package enum Action: BindableAction {
    case editDurationButtonTapped(DurationField)
    case timeInput(PresentationAction<TimeInputFeature.Action>)
    case binding(BindingAction<State>)
    case cancelButtonTapped
    case customizeBreaksButtonTapped
    case delegate(Delegate)
    case doneButtonTapped
    case useFirstBreakForAllButtonTapped

    @CasePathable
    package enum Delegate {
      case cancelled
      case committed(SetupTiming)
    }
  }

  package var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case let .editDurationButtonTapped(field):
        state.editedDuration = field
        let duration: NewGameFeature.DurationDraft
        let title: String
        switch field {
        case .quarter:
          duration = state.timing.periodDuration
          title = "Quarter length"
        case .allBreaks:
          duration = state.timing.firstBreakDuration
          title = "Break length"
        case .firstBreak:
          duration = state.timing.firstBreakDuration
          title = "After quarter 1"
        case .halfTime:
          duration = state.timing.halfTimeDuration
          title = "Half time"
        case .secondBreak:
          duration = state.timing.secondBreakDuration
          title = "After quarter 3"
        }
        state.timeInput = .init(
          title: title,
          totalSeconds: duration.totalSeconds ?? 0,
          allowedSeconds: (field == .quarter ? 1 : 0) ... 5999
        )
      case let .timeInput(.presented(.delegate(.committed(seconds)))):
        let duration = NewGameFeature.DurationDraft(totalSeconds: seconds)
        switch state.editedDuration {
        case .quarter: state.timing.periodDuration = duration
        case .allBreaks:
          state.timing.firstBreakDuration = duration
          state.timing.halfTimeDuration = duration
          state.timing.secondBreakDuration = duration
        case .firstBreak: state.timing.firstBreakDuration = duration
        case .halfTime: state.timing.halfTimeDuration = duration
        case .secondBreak: state.timing.secondBreakDuration = duration
        case nil: break
        }
        state.timeInput = nil
        state.editedDuration = nil
      case .timeInput(.presented(.delegate(.cancelled))), .timeInput(.dismiss):
        state.timeInput = nil
        state.editedDuration = nil
      case .timeInput:
        break
      case .binding:
        if !state.timing.customizesBreaks {
          state.timing.halfTimeDuration = state.timing.firstBreakDuration
          state.timing.secondBreakDuration = state.timing.firstBreakDuration
        }
      case .cancelButtonTapped:
        return .send(.delegate(.cancelled))
      case .customizeBreaksButtonTapped:
        state.timing.customizesBreaks = true
      case .delegate:
        break
      case .doneButtonTapped:
        guard state.timing.isValid else { return .none }
        return .send(.delegate(.committed(state.timing)))
      case .useFirstBreakForAllButtonTapped:
        state.timing.halfTimeDuration = state.timing.firstBreakDuration
        state.timing.secondBreakDuration = state.timing.firstBreakDuration
        state.timing.customizesBreaks = false
      }
      return .none
    }
    .ifLet(\.$timeInput, action: \.timeInput) { TimeInputFeature() }
  }

  package init() {}
}

package struct SetupTimingSummaryView: View {
  package var timing: SetupTiming
  package var edit: () -> Void
  package var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(timing.summary)
        Spacer()
        Button("Edit", action: edit)
          .buttonStyle(.borderless)
          .accessibilityLabel("Edit timing")
      }
      HStack {
        Text("Auto start breaks")
        Image(systemName: timing.breakStartPolicy == .automatic ? "checkmark.circle.fill" : "xmark.circle.fill")
      }
      .font(.subheadline).foregroundStyle(.secondary)
    }
    .setupCardStyle()
  }

  package init(timing: SetupTiming, edit: @escaping () -> Void) {
    self.timing = timing
    self.edit = edit
  }
}

package struct SetupTimingEditorView: View {
  @Bindable package var store: StoreOf<SetupTimingFeature>
  package var body: some View {
    NavigationStack {
      SetupTimingView(store: store)
        .sheet(item: $store.scope(state: \.timeInput, action: \.timeInput)) {
          TimeInputView(store: $0)
        }
        .navigationTitle("Timing")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(role: .cancel) { store.send(.cancelButtonTapped) }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(role: .confirm) { store.send(.doneButtonTapped) }
              .disabled(!store.timing.isValid)
          }
        }
    }
    .presentationDetents([.large])
    #if os(macOS)
      .frame(width: 560, height: 520)
    #endif
  }

  package init(store: StoreOf<SetupTimingFeature>) {
    self.store = store
  }
}
