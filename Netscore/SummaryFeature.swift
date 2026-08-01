import ComposableArchitecture
import Foundation

@Reducer
struct SummaryFeature {
  @ObservableState
  struct State: Equatable {
    var endedAt: Date
    var startedAt: Date
    var teamAName: String
    var teamAScore: Int
    var teamBName: String
    var teamBScore: Int

    var resultTitle: String {
      if teamAScore == teamBScore {
        return "Draw"
      } else if teamAScore > teamBScore {
        return "\(teamAName) win"
      } else {
        return "\(teamBName) win"
      }
    }
  }

  enum Action {
    case newGameButtonTapped
  }

  var body: some Reducer<State, Action> {
    Reduce { _, action in
      switch action {
      case .newGameButtonTapped:
        return .none
      }
    }
  }
}
