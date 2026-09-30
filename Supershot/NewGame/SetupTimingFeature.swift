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
    var timing: SetupTiming
  }
  enum Action: BindableAction {
    case allBreakPresetButtonTapped(Int)
    case binding(BindingAction<State>)
    case cancelButtonTapped
    case customizeBreaksButtonTapped
    case delegate(Delegate)
    case doneButtonTapped
    case firstBreakPresetButtonTapped(Int)
    case halfTimePresetButtonTapped(Int)
    case periodPresetButtonTapped(Int)
    case secondBreakPresetButtonTapped(Int)
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
      case .binding:
        if !state.timing.customizesBreaks {
          state.timing.halfTimeDuration = state.timing.firstBreakDuration
          state.timing.secondBreakDuration = state.timing.firstBreakDuration
        }
      case let .allBreakPresetButtonTapped(seconds):
        state.timing.firstBreakDuration = .init(totalSeconds: seconds)
        state.timing.halfTimeDuration = state.timing.firstBreakDuration
        state.timing.secondBreakDuration = state.timing.firstBreakDuration
      case .cancelButtonTapped:
        return .send(.delegate(.cancelled))
      case .customizeBreaksButtonTapped:
        state.timing.customizesBreaks = true
      case .delegate:
        break
      case .doneButtonTapped:
        guard state.timing.isValid else { return .none }
        return .send(.delegate(.committed(state.timing)))
      case let .firstBreakPresetButtonTapped(seconds):
        state.timing.firstBreakDuration = .init(totalSeconds: seconds)
      case let .halfTimePresetButtonTapped(seconds):
        state.timing.halfTimeDuration = .init(totalSeconds: seconds)
      case let .periodPresetButtonTapped(seconds):
        state.timing.periodDuration = .init(totalSeconds: seconds)
      case let .secondBreakPresetButtonTapped(seconds):
        state.timing.secondBreakDuration = .init(totalSeconds: seconds)
      case .useFirstBreakForAllButtonTapped:
        state.timing.halfTimeDuration = state.timing.firstBreakDuration
        state.timing.secondBreakDuration = state.timing.firstBreakDuration
        state.timing.customizesBreaks = false
      }
      return .none
    }
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
