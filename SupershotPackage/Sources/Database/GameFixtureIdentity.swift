import Foundation
import GameCore

/// Match what the schedule displays: the same two teams in either order,
/// at the same minute. Court, division and lifecycle do not create a new fixture.
package nonisolated struct GameFixtureIdentity: Hashable, Sendable {
  private let teams: Set<Team.ID>
  private let minute: Int64

  package init(teamAID: Team.ID, teamBID: Team.ID, scheduledAt: Date) {
    teams = [teamAID, teamBID]
    minute = Int64(floor(scheduledAt.timeIntervalSince1970 / 60))
  }

  package init?(game: Game) {
    guard let scheduledAt = game.scheduledAt else { return nil }
    self.init(teamAID: game.teamAID, teamBID: game.teamBID, scheduledAt: scheduledAt)
  }
}
