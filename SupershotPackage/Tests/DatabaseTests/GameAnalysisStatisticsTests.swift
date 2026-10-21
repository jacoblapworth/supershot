import CustomDump
@testable import Database
import Dependencies
import DependenciesTestSupport
import Foundation
import GameCore
@testable import SharedModels
import SQLiteData
import Testing
import TestSupport

extension SupershotTestSuite {
  @MainActor
  struct GameAnalysisStatisticsTests {
    private let teamAID = UUID(-1)
    private let teamBID = UUID(-2)

    @Test
    func weightedLeadsAndGoalRuns() {
      let goals = makeGoals([(true, 2), (true, 2), (false, 1), (false, 2), (false, 2), (true, 1)])
      let statistics = summarize(goals)
      expectNoDifference(statistics.teamA.biggestLead, 4)
      expectNoDifference(statistics.teamB.biggestLead, 1)
      expectNoDifference(statistics.teamA.longestScoringRun, 2)
      expectNoDifference(statistics.teamB.longestScoringRun, 3)
    }

    @Test
    func emptyOneSidedAndAlternatingScoring() {
      let empty = summarize([])
      expectNoDifference(empty.teamA.biggestLead, 0)
      expectNoDifference(empty.teamB.longestScoringRun, 0)
      expectNoDifference(empty.teamA.averageTimeToGoalSeconds, nil)
      expectNoDifference(
        empty.teamA.centrePass,
        CentrePassStatistics(
          conversions: 0, inferredTurnovers: 0, opportunities: 0
        )
      )
      let oneSided = summarize(makeGoals([(true, 2), (true, 1)]))
      expectNoDifference(oneSided.teamA.biggestLead, 3)
      expectNoDifference(oneSided.teamA.longestScoringRun, 2)
      expectNoDifference(oneSided.teamB.biggestLead, 0)
      expectNoDifference(oneSided.teamB.longestScoringRun, 0)
      let alternating = summarize(makeGoals([(true, 1), (false, 1), (true, 1), (false, 1)]))
      expectNoDifference(alternating.teamA.longestScoringRun, 1)
      expectNoDifference(alternating.teamB.longestScoringRun, 1)
    }

    @Test
    func gameRunsSpanQuartersAndAveragesUseGoalSamples() {
      var goals = makeGoals([(true, 1), (true, 2), (true, 1)])
      goals[0].elapsedSeconds = 10
      goals[1].elapsedSeconds = 30
      goals[2].gamePeriodID = UUID(-11)
      goals[2].elapsedSeconds = 60
      let wholeGame = summarize(goals)
      let firstQuarter = summarize(Array(goals.prefix(2)))
      let secondQuarter = summarize([goals[2]])
      expectNoDifference(wholeGame.teamA.longestScoringRun, 3)
      expectNoDifference(firstQuarter.teamA.longestScoringRun, 2)
      expectNoDifference(secondQuarter.teamA.longestScoringRun, 1)
      expectNoDifference(wholeGame.teamA.biggestLead, 4)
      expectNoDifference(secondQuarter.teamA.biggestLead, 1)
      expectNoDifference(wholeGame.teamA.averageTimeToGoalSeconds, 30)
      expectNoDifference(firstQuarter.teamA.averageTimeToGoalSeconds, 15)
      expectNoDifference(secondQuarter.teamA.averageTimeToGoalSeconds, 60)
    }

    @Test
    func missingCentrePassDoesNotHideOtherStatistics() {
      var goals = makeGoals([(true, 2), (false, 1)])
      goals[1].centrePassTeamID = nil
      let statistics = summarize(goals)
      expectNoDifference(statistics.teamA.centrePass, nil)
      expectNoDifference(statistics.teamB.centrePass, nil)
      expectNoDifference(statistics.teamA.biggestLead, 2)
      expectNoDifference(statistics.teamB.longestScoringRun, 1)
      expectNoDifference(statistics.teamB.averageTimeToGoalSeconds, 10)
    }

    @Test
    func queriesShareOrderedScopedStatisticsAndUndo() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let periods = testGamePeriods(gameID: UUID(-1), durationSeconds: 900)
      var goals = makeGoals([(true, 2), (true, 2), (false, 1), (false, 2), (false, 2), (true, 1)])
      // All goals in a quarter share a playing-time timestamp. createdAt breaks ties.
      for index in goals.indices {
        goals[index].gamePeriodID = periods[index < 2 ? 0 : 1].id
        goals[index].elapsedSeconds = 10
      }
      goals[2].centrePassTeamID = nil
      let recordedGoals = goals
      try await database.write { db in
        try db.seed {
          Team(id: teamAID, name: "A")
          Team(id: teamBID, name: "B")
          Game(
            id: UUID(-1), startedAt: Date(timeIntervalSince1970: 0),
            teamAID: teamAID, teamBID: teamBID
          )
        }
        try GamePeriod.insert { periods }.execute(db)
        // Deliberately insert backwards to verify snapshot ordering.
        try Goal.insert { recordedGoals.reversed() }.execute(db)
      }
      let live = try await database.read {
        try GameAnalysisRequest(gameID: UUID(-1)).fetch($0).analysis
      }
      expectNoDifference(live.statistics.teamA.biggestLead, 4)
      expectNoDifference(live.statistics.teamB.biggestLead, 1)
      expectNoDifference(live.statistics.teamB.longestScoringRun, 3)
      expectNoDifference(live.statisticsByPeriod[1]?.teamA.biggestLead, 4)
      expectNoDifference(live.statisticsByPeriod[2]?.teamB.biggestLead, 5)
      expectNoDifference(live.statisticsByPeriod[2]?.teamA.biggestLead, 0)
      expectNoDifference(live.statistics.teamA.centrePass, nil)
      expectNoDifference(live.statisticsByPeriod[1]?.teamA.centrePass?.conversions, 2)
      expectNoDifference(live.statisticsByPeriod[2]?.teamA.centrePass, nil)
      expectNoDifference(live.statisticsByPeriod[3]?.teamA.longestScoringRun, 0)
      expectNoDifference(live.statisticsByPeriod[3]?.teamA.averageTimeToGoalSeconds, nil)

      try await database.write { db in
        try Game.find(UUID(-1)).update { $0.endedAt = #bind(Date(timeIntervalSince1970: 1000)) }
          .execute(
            db
          )
      }
      let completed = try await database.read {
        try GameDetailRequest(gameID: UUID(-1)).fetch($0).detail
      }
      expectNoDifference(completed?.analysis.statistics, live.statistics)
      expectNoDifference(completed?.analysis.statisticsByPeriod, live.statisticsByPeriod)

      try await database.write { db in
        try Goal.find(recordedGoals[4].id).delete().execute(db)
      }
      let undone = try await database.read {
        try GameAnalysisRequest(gameID: UUID(-1)).fetch($0).analysis
      }
      expectNoDifference(undone.statistics.teamB.longestScoringRun, 2)
      expectNoDifference(undone.statistics.teamB.biggestLead, 0)
      expectNoDifference(undone.statisticsByPeriod[2]?.teamB.biggestLead, 3)
    }

    private func summarize(_ goals: [Goal]) -> CompletedGameStatistics {
      completedGameStatistics(goals: goals, teamAID: teamAID, teamBID: teamBID)
    }

    private func makeGoals(_ events: [(Bool, Int)]) -> [Goal] {
      events.enumerated().map { index, event in
        Goal(
          id: UUID(-100 - index), gameID: UUID(-1), gamePeriodID: UUID(-10),
          centrePassTeamID: teamAID, teamID: event.0 ? teamAID : teamBID,
          elapsedSeconds: (index + 1) * 10, points: event.1,
          createdAt: Date(timeIntervalSince1970: Double(index))
        )
      }
    }
  }
}
