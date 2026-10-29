import Database
import Foundation

package nonisolated enum GamesFilter: String, CaseIterable, Identifiable, Sendable {
  case all
  case planned
  case inProgress
  case completed

  package var id: Self {
    self
  }

  var title: LocalizedStringResource {
    switch self {
    case .all: "All"
    case .planned: "Planned"
    case .inProgress: "In Progress"
    case .completed: "Completed"
    }
  }

  var emptyTitle: LocalizedStringResource {
    switch self {
    case .all: "No games yet"
    case .planned: "No planned games"
    case .inProgress: "No in-progress games"
    case .completed: "No completed games"
    }
  }

  private static func ordered(_ lhs: GameListItem, _ rhs: GameListItem) -> Bool {
    if lhs.isPlanned != rhs.isPlanned {
      return lhs.isPlanned
    }
    if lhs.isPlanned {
      if lhs.scheduledAt != rhs.scheduledAt {
        return (lhs.scheduledAt ?? .distantFuture) < (rhs.scheduledAt ?? .distantFuture)
      }
      if lhs.scheduledAt == nil, lhs.createdAt != rhs.createdAt {
        return lhs.createdAt > rhs.createdAt
      }
    } else if lhs.startedAt != rhs.startedAt {
      return (lhs.startedAt ?? .distantPast) > (rhs.startedAt ?? .distantPast)
    }
    return lhs.id.uuidString > rhs.id.uuidString
  }

  func games(from games: [GameListItem]) -> [GameListItem] {
    switch self {
    case .all: games.filter(\.isPlanned).sorted(by: Self.ordered) + games.filter { !$0.isPlanned }
    case .planned: games.filter(\.isPlanned).sorted(by: Self.ordered)
    case .inProgress: games.filter(\.isInProgress)
    case .completed: games.filter(\.isCompleted)
    }
  }
}
