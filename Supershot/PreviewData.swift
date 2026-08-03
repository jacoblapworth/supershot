#if DEBUG
import Dependencies
import Foundation
import SQLiteData

extension DatabaseWriter {
  func seedDebugExamplesIfNeeded() throws {
    try write { db in
//      guard try Team.fetchCount(db) == 0 else { return }

      try db.seed {
        Team(id: UUID(1), name: "Ravens", colorHex: TeamColorPalette.blue)
        Team(id: UUID(2), name: "Swifts", colorHex: TeamColorPalette.red)
        Team(id: UUID(3), name: "Foxes", colorHex: "#34C759")
        Team(id: UUID(4), name: "Owls", colorHex: "#FF9500")
        Game(
          id: UUID(10),
          startedAt: Date(timeIntervalSince1970: 1_785_573_000),
          endedAt: Date(timeIntervalSince1970: 1_785_580_200),
          teamAID: UUID(1),
          teamABibColorHex: TeamColorPalette.blue,
          teamBID: UUID(2),
          teamBBibColorHex: TeamColorPalette.red,
          centrePassTeamID: UUID(2),
          periodDurationSeconds: 900,
          firstBreakDurationSeconds: 240,
          halfTimeDurationSeconds: 600,
          secondBreakDurationSeconds: 240,
          currentPeriod: 4,
          elapsedSeconds: 900,
          hasTimerStartedCurrentPeriod: true
        )
        Game(
          id: UUID(11),
          startedAt: Date(timeIntervalSince1970: 1_785_659_400),
          endedAt: nil,
          teamAID: UUID(3),
          teamABibColorHex: "#34C759",
          teamBID: UUID(4),
          teamBBibColorHex: "#FF9500",
          centrePassTeamID: UUID(3),
          periodDurationSeconds: 900,
          firstBreakDurationSeconds: 240,
          halfTimeDurationSeconds: 600,
          secondBreakDurationSeconds: 240,
          currentPeriod: 2,
          elapsedSeconds: 324,
          hasTimerStartedCurrentPeriod: true
        )
        Goal(
          id: UUID(20),
          gameID: UUID(10),
          centrePassTeamID: UUID(1),
          teamID: UUID(1),
          period: 1,
          elapsedSeconds: 120,
          points: 1,
          createdAt: Date(timeIntervalSince1970: 1_785_573_120)
        )
        Goal(
          id: UUID(21),
          gameID: UUID(10),
          centrePassTeamID: UUID(1),
          teamID: UUID(2),
          period: 2,
          elapsedSeconds: 480,
          points: 1,
          createdAt: Date(timeIntervalSince1970: 1_785_575_280)
        )
        Goal(
          id: UUID(22),
          gameID: UUID(10),
          centrePassTeamID: UUID(2),
          teamID: UUID(1),
          period: 4,
          elapsedSeconds: 720,
          points: 1,
          createdAt: Date(timeIntervalSince1970: 1_785_579_720)
        )
        Goal(
          id: UUID(23),
          gameID: UUID(11),
          centrePassTeamID: UUID(3),
          teamID: UUID(4),
          period: 1,
          elapsedSeconds: 240,
          points: 1,
          createdAt: Date(timeIntervalSince1970: 1_785_659_640)
        )
      }
    }
  }
}
#endif
