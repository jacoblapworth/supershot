import CustomDump
@testable import Database
import Dependencies
import DependenciesTestSupport
import Foundation
@testable import GameCore
import GRDB
@testable import ScoringFeature
@testable import SharedModels
import SQLiteData
import SwiftUI
import Testing
import TestSupport
import UI
@testable import WidgetSupport

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies {
    $0.uuid = .incrementing
  }) struct GameProgressFeatureTests {
    @Test
    func waitingPresentationDoesNotChangeQuarterClockOrLateScoring() {
      let periods = testGamePeriods(gameID: UUID(3), count: 2, breakDurationSeconds: 120)
      let boundary = Date(timeIntervalSince1970: 1000)
      let game = Game(
        id: UUID(3),
        startedAt: boundary.addingTimeInterval(-1020),
        teamAID: UUID(1),
        teamBID: UUID(2),
        isAwaitingCentrePassConfirmation: true,
        lateScoringPeriodNumber: 1,
        currentPhaseIndex: 2,
        waitingSince: boundary
      )
      let state = ScoringFeature.State(
        centrePassTeamID: UUID(1),
        currentPhaseIndex: 2,
        gameID: game.id,
        isShowingLastCentrePassBanner: true,
        lateScoringPeriodNumber: 1,
        periods: periods,
        startedAt: game.startedAt,
        teamA: .init(id: UUID(1), name: "Ravens"),
        teamB: .init(id: UUID(2), name: "Swifts"),
        waitingSince: boundary
      )
      #expect(state.timerViewState.waitingSince == boundary)
      #expect(state.timeRemainingSeconds == 900)
      #expect(state.elapsedSeconds == 0)
      #expect(state.scoringContext == .completedPeriod(number: 1))
      #expect(state.canScoreGoal)
      #expect(!state.canStartOrResume)
      #expect(state.scoringToolbarState.content != .none)
    }

    @Test
    func resumableProgressFieldsHaveSafeDefaults() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)

      try await database.write { db in
        try db.seed {
          Team(id: UUID(-1), name: "Ravens", colorHex: ColorPalette.blue.hex())
          Team(id: UUID(-2), name: "Swifts", colorHex: ColorPalette.red.hex())
          Game(
            id: UUID(-1),
            startedAt: Date(timeIntervalSince1970: 1000),
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
      expectNoDifference(state.teamA.bibColor, Color(hex: "#AF52DE"))
      expectNoDifference(state.teamB.bibColor, Color(hex: "#FF9500"))
    }

    @Test
    func breakSnapshotRehydratesPausedInTheCompletedQuartersOrder() {
      let ravens = Team(id: UUID(-1), name: "Ravens", colorHex: ColorPalette.blue.hex())
      let swifts = Team(id: UUID(-2), name: "Swifts", colorHex: ColorPalette.red.hex())
      let snapshot = GameSnapshot(
        game: Game(
          id: UUID(-3),
          startedAt: Date(timeIntervalSince1970: 1000),
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
      expectNoDifference(state.currentPhase.isBreak, true)
      expectNoDifference(state.currentDurationSeconds, 600)
      expectNoDifference(state.elapsedSeconds, 125)
      expectNoDifference(state.isShowingLastCentrePassBanner, true)
      expectNoDifference(state.courtLayout.left.id, state.teamB.id)
      expectNoDifference(state.isTimerRunning, false)
    }
  }
}
