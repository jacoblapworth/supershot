import ComposableArchitecture
import Foundation

@Reducer
struct TimeInputFeature {
  nonisolated enum Unit: Equatable, Sendable {
    case minutes
    case seconds
  }

  @ObservableState
  struct State: Equatable {
    var title: String
    var minutes: String
    var seconds: String
    var selectedUnit: Unit
    var replacesNextDigit = true
    var allowedSeconds: ClosedRange<Int>
    var isSaving = false
    var errorMessage: String?

    init(
      title: String, totalSeconds: Int, allowedSeconds: ClosedRange<Int>,
      selectedUnit: Unit = .minutes
    ) {
      self.title = title
      minutes = String(totalSeconds / 60)
      seconds = String(totalSeconds % 60)
      self.allowedSeconds = allowedSeconds
      self.selectedUnit = selectedUnit
    }

    var totalSeconds: Int { (Int(minutes) ?? 0) * 60 + (Int(seconds) ?? 0) }
    var isValid: Bool { allowedSeconds.contains(totalSeconds) }
    var enabledQuickAdds: Set<Int> { Set([1, 10, 30].filter { canAdd($0) }) }
    var selectedText: String {
      get { selectedUnit == .minutes ? minutes : seconds }
      set {
        if selectedUnit == .minutes { minutes = newValue } else { seconds = newValue }
      }
    }
    func canAdd(_ amount: Int) -> Bool {
      totalSeconds + amount * (selectedUnit == .minutes ? 60 : 1) <= allowedSeconds.upperBound
    }
    mutating func normalize() {
      let total = totalSeconds
      minutes = String(total / 60)
      seconds = String(total % 60)
    }
  }

  enum Action {
    case backspaceButtonTapped
    case cancelButtonTapped
    case delegate(Delegate)
    case digitButtonTapped(Int)
    case doneButtonTapped
    case quickAddButtonTapped(Int)
    case unitButtonTapped(Unit)

    @CasePathable
    enum Delegate {
      case cancelled
      case committed(Int)
    }
  }

  var body: some Reducer<State, Action> {
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
      case .digitButtonTapped(let digit):
        guard (0...9).contains(digit) else { return .none }
        let existing = state.replacesNextDigit ? "" : state.selectedText
        guard existing.count < 2 else { return .none }
        state.selectedText = existing + String(digit)
        state.replacesNextDigit = false
        state.errorMessage = nil
      case .doneButtonTapped:
        guard state.isValid else { return .none }
        state.normalize()
        return .send(.delegate(.committed(state.totalSeconds)))
      case .quickAddButtonTapped(let amount):
        guard [1, 10, 30].contains(amount), state.canAdd(amount) else { return .none }
        let total = state.totalSeconds + amount * (state.selectedUnit == .minutes ? 60 : 1)
        state.minutes = String(total / 60)
        state.seconds = String(total % 60)
        state.replacesNextDigit = true
        state.errorMessage = nil
      case .unitButtonTapped(let unit):
        state.normalize()
        state.selectedUnit = unit
        state.replacesNextDigit = true
      }
      return .none
    }
  }
}
