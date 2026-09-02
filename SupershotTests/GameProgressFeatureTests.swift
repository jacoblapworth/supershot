import CustomDump
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import Supershot
import DependenciesTestSupport

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies {
    $0.uuid = .incrementing
  }) struct GameProgressFeatureTests {
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
            teamBBibColorHex: "#FF9500"
          )
        }
        try GamePeriod.insert {
          testGamePeriods(
            gameID: UUID(-1),
            durationSeconds: 900,
            breakDurations: [240, 600, 240]
          )
        }
        .execute(db)
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
          isAwaitingCentrePassConfirmation: true,
          currentPhaseIndex: 3,
          elapsedSeconds: 125,
          timerEndsAt: nil
        ),
        goals: [],
        periods: testGamePeriods(
          gameID: UUID(-3),
          durationSeconds: 900,
          breakDurations: [240, 600, 240]
        ),
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
