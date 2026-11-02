import Database
import Foundation

nonisolated struct CompletedGameSection: Equatable, Identifiable {
  var day: Date
  var games: [GameListItem]

  var id: Date {
    day
  }

  static func sections(
    from games: [GameListItem],
    calendar: Calendar = .autoupdatingCurrent
  ) -> [Self] {
    var gamesByDay: [Date: [GameListItem]] = [:]
    for game in games {
      guard let endedAt = game.endedAt else { continue }
      let day = calendar.startOfDay(for: game.startedAt ?? endedAt)
      gamesByDay[day, default: []].append(game)
    }
    return gamesByDay.keys.sorted(by: >).map { day in
      Self(day: day, games: gamesByDay[day, default: []].sorted { lhs, rhs in
        let lhsDate = lhs.startedAt ?? lhs.endedAt ?? .distantPast
        let rhsDate = rhs.startedAt ?? rhs.endedAt ?? .distantPast
        return lhsDate == rhsDate ? lhs.id.uuidString > rhs.id.uuidString : lhsDate > rhsDate
      })
    }
  }
}
