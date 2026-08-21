#if DEBUG
import Dependencies
import Foundation
import GRDB
import SQLiteData

extension DatabaseWriter {
  func seedDebugExamplesIfNeeded() throws {
    try write { db in
      guard try Team.fetchCount(db) == 0 else { return }

      let completedStartedAt = Date(timeIntervalSince1970: 1_785_573_000)
      let inProgressStartedAt = Date(timeIntervalSince1970: 1_785_659_400)

      try db.seed {
        Team(id: UUID(1), name: "North London Ravens", colorHex: TeamColorPalette.blue)
        Team(id: UUID(2), name: "Westminster Swifts", colorHex: TeamColorPalette.red)
        Team(id: UUID(3), name: "Hackney Foxes", colorHex: "#34C759")
        Team(id: UUID(4), name: "Camden Owls", colorHex: "#FF9500")
        Game(
          id: UUID(10),
          startedAt: completedStartedAt,
          endedAt: completedStartedAt.addingTimeInterval(35 * 60),
          teamAID: UUID(1),
          teamABibColorHex: TeamColorPalette.blue,
          teamBID: UUID(2),
          teamBBibColorHex: TeamColorPalette.red,
          centrePassTeamID: UUID(1),
          periodDurationSeconds: MockGameData.periodDurationSeconds,
          firstBreakDurationSeconds: MockGameData.breakDurationSeconds,
          halfTimeDurationSeconds: MockGameData.breakDurationSeconds,
          secondBreakDurationSeconds: MockGameData.breakDurationSeconds,
          currentPhaseIndex: 6,
          elapsedSeconds: MockGameData.periodDurationSeconds,
          timerEndsAt: nil
        )
        Game(
          id: UUID(11),
          startedAt: inProgressStartedAt,
          endedAt: nil,
          teamAID: UUID(3),
          teamABibColorHex: "#34C759",
          teamBID: UUID(4),
          teamBBibColorHex: "#FF9500",
          centrePassTeamID: UUID(3),
          periodDurationSeconds: MockGameData.periodDurationSeconds,
          firstBreakDurationSeconds: MockGameData.breakDurationSeconds,
          halfTimeDurationSeconds: MockGameData.breakDurationSeconds,
          secondBreakDurationSeconds: MockGameData.breakDurationSeconds,
          currentPhaseIndex: 2,
          elapsedSeconds: 324,
          timerEndsAt: nil
        )
      }

      try insertMockGoals(
        db: db,
        events: MockGameData.goalEvents(throughPeriod: 4),
        gameID: UUID(10),
        idOffset: 100,
        startedAt: completedStartedAt,
        teamAID: UUID(1),
        teamBID: UUID(2)
      )
      try insertMockGoals(
        db: db,
        events: MockGameData.goalEvents(
          throughPeriod: 2,
          elapsedSecondsInFinalPeriod: 324
        ),
        gameID: UUID(11),
        idOffset: 200,
        startedAt: inProgressStartedAt,
        teamAID: UUID(3),
        teamBID: UUID(4)
      )
    }
  }
}

private func insertMockGoals(
  db: Database,
  events: [MockGameData.GoalEvent],
  gameID: Game.ID,
  idOffset: Int,
  startedAt: Date,
  teamAID: Team.ID,
  teamBID: Team.ID
) throws {
  for (index, event) in events.enumerated() {
    let secondsBeforePeriod = (event.period - 1)
      * (MockGameData.periodDurationSeconds + MockGameData.breakDurationSeconds)
    try Goal.insert {
      Goal(
        id: UUID(idOffset + index),
        gameID: gameID,
        centrePassTeamID: event.centrePassTeamA ? teamAID : teamBID,
        teamID: event.teamAScored ? teamAID : teamBID,
        quarterNumber: event.period,
        elapsedSeconds: event.elapsedSeconds,
        points: 1,
        createdAt: startedAt.addingTimeInterval(
          TimeInterval(secondsBeforePeriod + event.elapsedSeconds)
        )
      )
    }
    .execute(db)
  }
}
#endif
