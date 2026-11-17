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
  package typealias Duration = NewGameFeature.DurationDraft

  package var breakStartPolicy = BreakStartPolicy.automatic
  package var customizesBreaks = false
  package private(set) var periodCount = GamePeriodFormat.defaultCount
  package var periodDuration = Duration(totalSeconds: 480)
  package var sharedBreakDuration = Duration(totalSeconds: 60)
  package var individualBreakDurations: [Duration] = []

  package var breakCount: Int {
    max(0, periodCount - 1)
  }

  package var breakDurations: [Duration] {
    customizesBreaks
      ? individualBreakDurations
      : Array(repeating: sharedBreakDuration, count: breakCount)
  }

  package var isValid: Bool {
    GamePeriodFormat.editableCounts.contains(periodCount)
      && (periodDuration.totalSeconds ?? 0) > 0
      && breakDurations.count == breakCount
      && breakDurations.allSatisfy { $0.totalSeconds != nil }
  }

  package var periodTitle: String {
    GamePeriodFormat.title(for: periodCount)
  }

  package func breakTitle(at index: Int) -> String {
    if periodCount == 4, index == 1 {
      return "Half time"
    }
    return "After \(periodTitle.lowercased()) \(index + 1)"
  }

  package var summary: String {
    let playingTime = "\(periodCount) × \(periodDuration.formatted)"
    let breaks = breakDurations.map(\.formatted)
    guard let first = breaks.first else { return playingTime }
    if Set(breaks).count == 1 {
      return "\(playingTime) · \(first) \(breakCount == 1 ? "break" : "breaks")"
    }
    let details = breaks.enumerated().map { index, duration in
      "\(breakTitle(at: index)) \(duration)"
    }
    return "\(playingTime) · \(details.joined(separator: " · "))"
  }

  package init() {}

  package mutating func resize(to count: Int) {
    guard GamePeriodFormat.editableCounts.contains(count) else { return }
    if customizesBreaks {
      individualBreakDurations = Array(individualBreakDurations.prefix(count - 1))
      individualBreakDurations += Array(
        repeating: sharedBreakDuration,
        count: count - 1 - individualBreakDurations.count
      )
    }
    periodCount = count
  }

  package mutating func restoreBreaks(from periods: [GamePeriod]) {
    periodCount = periods.count
    let breaks = periods.dropLast().map { $0.breakAfterDurationSeconds ?? 0 }
    if let first = breaks.first {
      sharedBreakDuration = Duration(totalSeconds: first)
    }
    customizesBreaks = Set(breaks).count > 1
    individualBreakDurations = customizesBreaks ? breaks.map(Duration.init(totalSeconds:)) : []
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
    case quarter, allBreaks, individualBreak(Int)
  }

  package enum Action: BindableAction {
    case editDurationButtonTapped(DurationField)
    case timeInput(PresentationAction<TimeInputFeature.Action>)
    case binding(BindingAction<State>)
    case cancelButtonTapped
    case periodCountChanged(Int)
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
        let duration: NewGameFeature.DurationDraft
        let title: String
        switch field {
        case .quarter:
          duration = state.timing.periodDuration
          title = "\(state.timing.periodTitle) length"
        case .allBreaks:
          duration = state.timing.sharedBreakDuration
          title = "Break length"
        case let .individualBreak(index):
          guard state.timing.individualBreakDurations.indices.contains(index) else { return .none }
          duration = state.timing.individualBreakDurations[index]
          title = state.timing.breakTitle(at: index)
        }
        state.editedDuration = field
        state.timeInput = .init(
          title: title,
          totalSeconds: duration.totalSeconds ?? 0,
          allowedSeconds: (field == .quarter ? 1 : 0) ... 5999
        )
      case let .timeInput(.presented(.delegate(.committed(seconds)))):
        let duration = NewGameFeature.DurationDraft(totalSeconds: seconds)
        switch state.editedDuration {
        case .quarter: state.timing.periodDuration = duration
        case .allBreaks: state.timing.sharedBreakDuration = duration
        case let .individualBreak(index):
          if state.timing.individualBreakDurations.indices.contains(index) {
            state.timing.individualBreakDurations[index] = duration
          }
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
        break
      case let .periodCountChanged(count):
        state.timing.resize(to: count)
      case .cancelButtonTapped:
        return .send(.delegate(.cancelled))
      case .customizeBreaksButtonTapped:
        state.timing.individualBreakDurations = state.timing.breakDurations
        state.timing.customizesBreaks = true
      case .delegate:
        break
      case .doneButtonTapped:
        guard state.timing.isValid else { return .none }
        return .send(.delegate(.committed(state.timing)))
      case .useFirstBreakForAllButtonTapped:
        if let first = state.timing.individualBreakDurations.first {
          state.timing.sharedBreakDuration = first
        }
        state.timing.individualBreakDurations = []
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
      if timing.breakCount > 0 {
        HStack {
          Text("Auto start breaks")
          Image(systemName: timing.breakStartPolicy == .automatic ? "checkmark.circle.fill" : "xmark.circle.fill")
        }
        .font(.subheadline).foregroundStyle(.secondary)
      }
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
