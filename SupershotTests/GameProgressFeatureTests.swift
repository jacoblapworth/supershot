import CustomDump
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct GameProgressFeatureTests {
    @Test
    func resumableProgressFieldsHaveSafeDefaults() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)

      try await database.write { db in
        try db.seed {
          Team(id: UUID(-1), name: "Ravens", colorHex: TeamColorPalette.blue)
          Team(id: UUID(-2), name: "Swifts", colorHex: TeamColorPalette.red)
          Game(
            id: UUID(-1),
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: nil,
            teamAID: UUID(-1),
            teamABibColorHex: "#AF52DE",
            teamBID: UUID(-2),
            teamBBibColorHex: "#FF9500",
            periodDurationSeconds: 900,
            firstBreakDurationSeconds: 240,
            halfTimeDurationSeconds: 600,
            secondBreakDurationSeconds: 240
          )
        }
      }

      let game = try await database.read { db in
        try Game.find(UUID(-1)).fetchOne(db)
      }
      expectNoDifference(game?.currentPhaseIndex, 0)
      expectNoDifference(game?.elapsedSeconds, 0)
      expectNoDifference(game?.isAwaitingCentrePassConfirmation, false)
      expectNoDifference(game?.centrePassTeamID, nil)

      let snapshot = try await database.read { db in
        try GameSnapshot.fetch(db, gameID: UUID(-1))
      }
      let state = ScoringFeature.State(snapshot: snapshot)
      expectNoDifference(state.centrePassTeamID, UUID(-1))
      expectNoDifference(state.teamA.bibColorHex, "#AF52DE")
      expectNoDifference(state.teamB.bibColorHex, "#FF9500")
    }

    @Test
    func breakSnapshotRehydratesPausedInTheCompletedQuartersOrder() {
      let ravens = Team(id: UUID(-1), name: "Ravens", colorHex: TeamColorPalette.blue)
      let swifts = Team(id: UUID(-2), name: "Swifts", colorHex: TeamColorPalette.red)
      let snapshot = GameSnapshot(
        game: Game(
          id: UUID(-3),
          startedAt: Date(timeIntervalSince1970: 1_000),
          endedAt: nil,
          teamAID: ravens.id,
          teamBID: swifts.id,
          centrePassTeamID: ravens.id,
          periodDurationSeconds: 900,
          firstBreakDurationSeconds: 240,
          halfTimeDurationSeconds: 600,
          secondBreakDurationSeconds: 240,
          isAwaitingCentrePassConfirmation: true,
          currentPhaseIndex: 3,
          elapsedSeconds: 125,
          timerEndsAt: nil
        ),
        goals: [],
        teamA: ravens,
        teamB: swifts
      )

      let state = ScoringFeature.State(snapshot: snapshot)
      expectNoDifference(state.clockPhase, .breakTime)
      expectNoDifference(state.currentDurationSeconds, 600)
      expectNoDifference(state.elapsedSeconds, 125)
      expectNoDifference(state.isShowingLastCentrePassBanner, true)
      expectNoDifference(state.isShowingOriginalTeamOrder, false)
      expectNoDifference(state.isTimerRunning, false)
    }

  }
}
