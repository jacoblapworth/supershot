import ComposableArchitecture
import Foundation

@Reducer
package struct TimeInputFeature {
  package nonisolated enum Unit: Equatable, Sendable {
    case minutes
    case seconds
  }

  @ObservableState
  package struct State: Equatable {
    package var title: String
    package var minutes: String
    package var seconds: String
    package var selectedUnit: Unit
    package var replacesNextDigit = true
    package var allowedSeconds: ClosedRange<Int>
    package var isSaving = false
    package var errorMessage: String?

    package init(
      title: String, totalSeconds: Int,
      allowedSeconds: ClosedRange<Int>,
      selectedUnit: Unit = .minutes
    ) {
      self.title = title
      minutes = String(totalSeconds / 60)
      seconds = String(totalSeconds % 60)
      self.allowedSeconds = allowedSeconds
      self.selectedUnit = selectedUnit
    }

    package var totalSeconds: Int {
      (Int(minutes) ?? 0) * 60 + (Int(seconds) ?? 0)
    }

    package var isValid: Bool {
      allowedSeconds.contains(totalSeconds)
    }

    package var enabledQuickAdds: Set<Int> {
      Set([1, 10, 30].filter { canAdd($0) })
    }

    package var selectedText: String {
      get { selectedUnit == .minutes ? minutes : seconds }
      set {
        if selectedUnit == .minutes {
          minutes = newValue
        } else {
          seconds = newValue
        }
      }
    }

    package func canAdd(_ amount: Int) -> Bool {
      totalSeconds + amount * (selectedUnit == .minutes ? 60 : 1) <= allowedSeconds.upperBound
    }

    package mutating func normalize() {
      let total = totalSeconds
      minutes = String(total / 60)
      seconds = String(total % 60)
    }
  }

  package enum Action {
    case backspaceButtonTapped
    case cancelButtonTapped
    case delegate(Delegate)
    case digitButtonTapped(Int)
    case doneButtonTapped
    case quickAddButtonTapped(Int)
    case unitButtonTapped(Unit)
    case textChanged(Unit, String)

    @CasePathable
    package enum Delegate {
      case cancelled
      case committed(Int)
    }
  }

  package var body: some Reducer<State, Action> {
    Reduce { state, action in
      guard !state.isSaving else { return .none }
      switch action {
      case .backspaceButtonTapped:
        state.selectedText = String(state.selectedText.dropLast())
        state.replacesNextDigit = false
        state.errorMessage = nil
      case .cancelButtonTapped:
        return .send(.delegate(.cancelled))
      case .delegate:
        break
      case let .digitButtonTapped(digit):
        guard (0 ... 9).contains(digit) else { return .none }
        let existing = state.replacesNextDigit ? "" : state.selectedText
        guard existing.count < 2 else { return .none }
        state.selectedText = existing + String(digit)
        state.replacesNextDigit = false
        state.errorMessage = nil
      case .doneButtonTapped:
        guard state.isValid else { return .none }
        state.normalize()
        return .send(.delegate(.committed(state.totalSeconds)))
      case let .quickAddButtonTapped(amount):
        guard [1, 10, 30].contains(amount), state.canAdd(amount) else { return .none }
        let total = state.totalSeconds + amount * (state.selectedUnit == .minutes ? 60 : 1)
        state.minutes = String(total / 60)
        state.seconds = String(total % 60)
        state.replacesNextDigit = true
        state.errorMessage = nil
      case let .textChanged(unit, text):
        let digits = String(text.filter { $0.isASCII && $0.isNumber }.prefix(2))
        if unit == .minutes {
          state.minutes = digits
        } else {
          state.seconds = digits
        }
        state.errorMessage = nil
      case let .unitButtonTapped(unit):
        state.normalize()
        state.selectedUnit = unit
        state.replacesNextDigit = true
      }
      return .none
    }
  }

  package init() {}
}
