import ComposableArchitecture
import CustomDump
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct GameDetailFeatureTests {
    @Test
    func completedGameDetailBuildsReverseChronologicalQuarterTimeline() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)

      let startedAt = Date(timeIntervalSince1970: 1_000)
      let endedAt = Date(timeIntervalSince1970: 2_000)
      try await database.write { db in
        try db.seed {
          Team(id: UUID(-1), name: "Ravens", colorHex: TeamColorPalette.blue)
          Team(id: UUID(-2), name: "Swifts", colorHex: TeamColorPalette.red)
          Game(
            id: UUID(-1),
            startedAt: startedAt,
            endedAt: endedAt,
            teamAID: UUID(-1),
            teamBID: UUID(-2),
            periodDurationSeconds: 900,
            firstBreakDurationSeconds: 240,
            halfTimeDurationSeconds: 600,
            secondBreakDurationSeconds: 240
          )
          Goal(
            id: UUID(-3),
            gameID: UUID(-1),
            centrePassTeamID: UUID(-2),
            teamID: UUID(-2),
            period: 2,
            elapsedSeconds: 30,
            points: 1,
            createdAt: Date(timeIntervalSince1970: 1_300)
          )
          Goal(
            id: UUID(-1),
            gameID: UUID(-1),
            centrePassTeamID: UUID(-1),
            teamID: UUID(-1),
            period: 1,
            elapsedSeconds: 100,
            points: 2,
            createdAt: Date(timeIntervalSince1970: 1_100)
          )
          Goal(
            id: UUID(-2),
            gameID: UUID(-1),
            centrePassTeamID: UUID(-1),
            teamID: UUID(-2),
            period: 1,
            elapsedSeconds: 200,
            points: 1,
            createdAt: Date(timeIntervalSince1970: 1_200)
          )
        }
      }

      let value = try await database.read { db in
        try GameDetailRequest(gameID: UUID(-1)).fetch(db)
      }

      expectNoDifference(
        value.detail,
        CompletedGameDetail(
          endedAt: endedAt,
          firstBreakDurationSeconds: 240,
          goalTimeline: GoalTimeline(
            quarters: [
              GoalTimelineQuarter(
                goals: [],
                period: 4,
                teamAQuarterScore: 0,
                teamBQuarterScore: 0
              ),
              GoalTimelineQuarter(
                goals: [],
                period: 3,
                teamAQuarterScore: 0,
                teamBQuarterScore: 0
              ),
              GoalTimelineQuarter(
                goals: [
                  GoalTimelineItem(
                    clockSecondsRemaining: 870,
                    id: UUID(-3),
                    period: 2,
                    points: 1,
                    scoringTeamBibColorHex: TeamColorPalette.red,
                    scoringTeamName: "Swifts",
                    scoringTeamSide: .teamB,
                    teamAScore: 2,
                    teamBScore: 2
                  )
                ],
                period: 2,
                teamAQuarterScore: 0,
                teamBQuarterScore: 1
              ),
              GoalTimelineQuarter(
                goals: [
                  GoalTimelineItem(
                    clockSecondsRemaining: 700,
                    id: UUID(-2),
                    period: 1,
                    points: 1,
                    scoringTeamBibColorHex: TeamColorPalette.red,
                    scoringTeamName: "Swifts",
                    scoringTeamSide: .teamB,
                    teamAScore: 2,
                    teamBScore: 1
                  ),
                  GoalTimelineItem(
                    clockSecondsRemaining: 800,
                    id: UUID(-1),
                    period: 1,
                    points: 2,
                    scoringTeamBibColorHex: TeamColorPalette.blue,
                    scoringTeamName: "Ravens",
                    scoringTeamSide: .teamA,
                    teamAScore: 2,
                    teamBScore: 0
                  ),
                ],
                period: 1,
                teamAQuarterScore: 2,
                teamBQuarterScore: 1
              ),
            ]
          ),
          halfTimeDurationSeconds: 600,
          id: UUID(-1),
          periodDurationSeconds: 900,
          secondBreakDurationSeconds: 240,
          startedAt: startedAt,
          statistics: CompletedGameStatistics(
            teamA: TeamGameStatistics(
              averageTimeToGoalSeconds: 100,
              centrePass: CentrePassStatistics(
                conversions: 1,
                inferredTurnovers: 1,
                opportunities: 2
              )
            ),
            teamB: TeamGameStatistics(
              averageTimeToGoalSeconds: 65,
              centrePass: CentrePassStatistics(
                conversions: 1,
                inferredTurnovers: 0,
                opportunities: 1
              )
            )
          ),
          teamABibColorHex: TeamColorPalette.blue,
          teamAName: "Ravens",
          teamAScore: 2,
          teamBBibColorHex: TeamColorPalette.red,
          teamBName: "Swifts",
          teamBScore: 2
        )
      )
    }

    @Test
    func liveGoalTimelineIncludesEmptyPlayedQuartersAndReflectsGoalChanges() async throws {
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
            teamBID: UUID(-2),
            periodDurationSeconds: 900,
            currentPeriod: 3
          )
          Goal(
            id: UUID(-1),
            gameID: UUID(-1),
            teamID: UUID(-1),
            period: 1,
            elapsedSeconds: 100,
            points: 1,
            createdAt: Date(timeIntervalSince1970: 1_100)
          )
        }
      }

      let initial = try await database.read { db in
        try GoalTimelineRequest(gameID: UUID(-1)).fetch(db).timeline
      }
      expectNoDifference(initial.quarters.map(\.period), [3, 2, 1])
      expectNoDifference(initial.quarters.map(\.goals.count), [0, 0, 1])
      expectNoDifference(initial.quarters.last?.teamAQuarterScore, 1)
      expectNoDifference(initial.quarters.last?.goals.first?.scoringTeamSide, .teamA)

      try await database.write { db in
        try Goal.insert {
          Goal(
            id: UUID(-2),
            gameID: UUID(-1),
            teamID: UUID(-2),
            period: 3,
            elapsedSeconds: 200,
            points: 2,
            createdAt: Date(timeIntervalSince1970: 1_200)
          )
        }
        .execute(db)
      }

      let afterGoal = try await database.read { db in
        try GoalTimelineRequest(gameID: UUID(-1)).fetch(db).timeline
      }
      expectNoDifference(afterGoal.quarters.first?.teamAQuarterScore, 0)
      expectNoDifference(afterGoal.quarters.first?.teamBQuarterScore, 2)
      expectNoDifference(afterGoal.quarters.first?.goals.first?.scoringTeamSide, .teamB)
      expectNoDifference(afterGoal.quarters.first?.goals.first?.teamAScore, 1)
      expectNoDifference(afterGoal.quarters.first?.goals.first?.teamBScore, 2)

      try await database.write { db in
        try Goal.find(UUID(-2)).delete().execute(db)
      }

      let afterUndo = try await database.read { db in
        try GoalTimelineRequest(gameID: UUID(-1)).fetch(db).timeline
      }
      expectNoDifference(afterUndo.quarters.first?.goals, [])
      expectNoDifference(afterUndo.quarters.first?.teamBQuarterScore, 0)
    }

    @Test
    func completedGameDetailKeepsLegacyCentrePassStatisticsUnavailable() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)

      try await database.write { db in
        try db.seed {
          Team(id: UUID(-1), name: "Ravens")
          Team(id: UUID(-2), name: "Swifts")
          Game(
            id: UUID(-1),
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 2_000),
            teamAID: UUID(-1),
            teamBID: UUID(-2),
            periodDurationSeconds: 900
          )
          Goal(
            id: UUID(-1),
            gameID: UUID(-1),
            teamID: UUID(-1),
            period: 1,
            elapsedSeconds: 42,
            points: 1,
            createdAt: Date(timeIntervalSince1970: 1_042)
          )
        }
      }

      let detail = try await database.read { db in
        try GameDetailRequest(gameID: UUID(-1)).fetch(db).detail
      }

      expectNoDifference(
        detail?.statistics,
        CompletedGameStatistics(
          teamA: TeamGameStatistics(
            averageTimeToGoalSeconds: 42,
            centrePass: nil
          ),
          teamB: TeamGameStatistics(
            averageTimeToGoalSeconds: nil,
            centrePass: nil
          )
        )
      )
    }
    @Test
    func detailDeleteButtonDelegatesDeletion() async {
      let store = TestStore(initialState: GameDetailFeature.State(gameID: UUID(3))) {
        GameDetailFeature()
      }

      await store.send(.deleteButtonTapped)
      await store.receive(.delegate(.deleteGameButtonTapped))
    }

  }
}
