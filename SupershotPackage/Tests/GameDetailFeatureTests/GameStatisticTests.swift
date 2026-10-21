import CustomDump
import Database
import GameAnalysis
import Testing

struct GameStatisticTests {
  @Test
  func barsCompareRatesRatherThanConversionCounts() {
    let a = TeamGameStatistics(
      centrePass: CentrePassStatistics(
        conversions: 1, inferredTurnovers: 1, opportunities: 2
      )
    )
    let b = TeamGameStatistics(
      centrePass: CentrePassStatistics(
        conversions: 3, inferredTurnovers: 3, opportunities: 6
      )
    )
    expectNoDifference(GameStatistic.centrePassConversion.teamAFraction(teamA: a, teamB: b), 0.5)
    expectNoDifference(GameStatistic.centrePassConversion.text(a), "1/2 · 50%")
  }

  @Test
  func barsRetainPrecisionAndHandleZeroAndUnavailable() {
    let a = TeamGameStatistics(averageTimeToGoalSeconds: 0.25, biggestLead: 4)
    let b = TeamGameStatistics(averageTimeToGoalSeconds: 0.75, biggestLead: 0)
    expectNoDifference(GameStatistic.averageTimeToGoal.teamAFraction(teamA: a, teamB: b), 0.25)
    expectNoDifference(GameStatistic.biggestLead.teamAFraction(teamA: a, teamB: b), 1)
    expectNoDifference(GameStatistic.biggestLead.teamAFraction(teamA: b, teamB: a), 0)
    expectNoDifference(GameStatistic.biggestLead.teamAFraction(teamA: b, teamB: b), nil)
    expectNoDifference(GameStatistic.centrePassConversion.teamAFraction(teamA: a, teamB: b), nil)
    expectNoDifference(GameStatistic.averageTimeToGoal.teamAFraction(teamA: a, teamB: .init()), nil)
    expectNoDifference(GameStatistic.averageTimeToGoal.accessibleText(.init()), "unavailable")
    expectNoDifference(
      GameStatistic.averageTimeToGoal.accessibleText(.init(averageTimeToGoalSeconds: 90)),
      "1 minute, 30 seconds"
    )
  }

  @Test
  func breakdownSelectsWholeGameOrQuarterSummary() {
    let wholeGame = CompletedGameStatistics(teamA: TeamGameStatistics(biggestLead: 4))
    let quarter = CompletedGameStatistics(teamB: TeamGameStatistics(biggestLead: 5))
    let analysis = GameAnalysis(statistics: wholeGame, statisticsByPeriod: [2: quarter])
    expectNoDifference(GameAnalysisBreakdown.wholeGame.statistics(in: analysis), wholeGame)
    expectNoDifference(GameAnalysisBreakdown.period(2).statistics(in: analysis), quarter)
    expectNoDifference(GameAnalysisBreakdown.period(3).statistics(in: analysis), .init())
  }
}
