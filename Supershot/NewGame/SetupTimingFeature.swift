import ComposableArchitecture
import SwiftUI

nonisolated struct SetupTiming: Equatable, Sendable {
  var customizesBreaks = false
  var firstBreakDuration = NewGameFeature.DurationDraft(totalSeconds: 60)
  var halfTimeDuration = NewGameFeature.DurationDraft(totalSeconds: 60)
  var periodDuration = NewGameFeature.DurationDraft(totalSeconds: 480)
  var secondBreakDuration = NewGameFeature.DurationDraft(totalSeconds: 60)

  var isValid: Bool {
    (periodDuration.totalSeconds ?? 0) > 0
      && firstBreakDuration.totalSeconds != nil
      && halfTimeDuration.totalSeconds != nil
      && secondBreakDuration.totalSeconds != nil
  }

  var summary: String {
    let breaks = [firstBreakDuration, halfTimeDuration, secondBreakDuration].map(\.formatted)
    if Set(breaks).count == 1 {
      return "4 × \(periodDuration.formatted) · \(breaks[0]) breaks"
    }
    return "4 × \(periodDuration.formatted) · Q1 break \(breaks[0]) · Half time \(breaks[1]) · Q3 break \(breaks[2])"
  }
}

@Reducer
struct SetupTimingFeature {
  @ObservableState
  struct State: Equatable {
    @Presents var timeInput: TimeInputFeature.State?
    var editedDuration: DurationField?
    var timing: SetupTiming
  }
  enum DurationField: Equatable {
    case quarter, allBreaks, firstBreak, halfTime, secondBreak
  }
  enum Action: BindableAction {
    case editDurationButtonTapped(DurationField)
    case timeInput(PresentationAction<TimeInputFeature.Action>)
    case binding(BindingAction<State>)
    case cancelButtonTapped
    case customizeBreaksButtonTapped
    case delegate(Delegate)
    case doneButtonTapped
    case useFirstBreakForAllButtonTapped

    @CasePathable
    enum Delegate {
      case cancelled
      case committed(SetupTiming)
    }
  }
  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .editDurationButtonTapped(let field):
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
          title: title, totalSeconds: duration.totalSeconds ?? 0,
          allowedSeconds: (field == .quarter ? 1 : 0)...5999)
      case .timeInput(.presented(.delegate(.committed(let seconds)))):
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
}

struct SetupTimingSummaryView: View {
  var timing: SetupTiming
  var edit: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Timing", systemImage: "timer").font(.headline)
        Spacer()
        Button("Edit", action: edit).accessibilityLabel("Edit timing")
      }
      Text(timing.summary).font(.subheadline).foregroundStyle(.secondary)
    }
    .setupCardStyle()
  }
}

struct SetupTimingEditorView: View {
  @Bindable var store: StoreOf<SetupTimingFeature>
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text(store.timing.summary).font(.subheadline).foregroundStyle(.secondary)
          SetupTimingView(store: store)
          if !store.timing.isValid {
            Text("Enter valid quarter and break durations.").foregroundStyle(.red)
          }
        }.padding()
      }
      .sheet(item: $store.scope(state: \.timeInput, action: \.timeInput)) {
        TimeInputView(store: $0)
      }
      .navigationTitle("Timing")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { store.send(.cancelButtonTapped) }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { store.send(.doneButtonTapped) }.disabled(!store.timing.isValid)
        }
      }
    }
    .presentationDetents([.large])
  }
}
