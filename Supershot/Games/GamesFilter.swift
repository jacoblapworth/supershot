import Foundation

nonisolated enum GamesFilter: String, CaseIterable, Identifiable, Sendable {
  case all
  case inProgress
  case completed

  var id: Self { self }

  var title: LocalizedStringResource {
    switch self {
    case .all: "All"
    case .inProgress: "In progress"
    case .completed: "Completed"
    }
  }

  var emptyTitle: LocalizedStringResource {
    switch self {
    case .all: "No games yet"
    case .inProgress: "No in-progress games"
    case .completed: "No completed games"
    }
  }

  func games(from games: [GameListItem]) -> [GameListItem] {
    switch self {
    case .all: games
    case .inProgress: games.filter { !$0.isCompleted }
    case .completed: games.filter { $0.isCompleted }
    }
  }
}
