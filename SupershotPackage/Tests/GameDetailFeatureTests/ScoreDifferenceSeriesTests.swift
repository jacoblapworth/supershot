import CustomDump
import Database
import Dependencies
import Foundation
import GameAnalysis
import GameCore
import Testing

@Suite struct ScoreDifferenceSeriesTests {
  @Test func weightedGoalsAndLeadChanges() {
    let series = ScoreDifferenceSeries(
      analysis: analysis(events: [
        (1, 10, 2, 0), (1, 20, 2, 1), (1, 30, 2, 3), (1, 40, 3, 3),
      ]))
    expectNoDifference(series.points.map(\.difference), [0, 2, 1, -1, 0])
    expectNoDifference(series.points.map(\.elapsedSeconds), [0, 10, 20, 30, 40])
    expectNoDifference(series.extent, 2)
  }

  @Test func sameSecondGoalsKeepCanonicalOrderAndInspectFinalScore() {
    let series = ScoreDifferenceSeries(
      analysis: analysis(events: [
        (1, 10, 2, 0), (1, 10, 2, 1), (1, 10, 2, 3), (1, 10, 3, 3),
      ]))
    expectNoDifference(series.moments.map(\.difference), [2, 1, -1, 0])
    expectNoDifference(Set(series.moments.map(\.id)).count, 4)
    expectNoDifference(series.nearestMoment(to: 10)?.difference, 0)
  }

  @Test func quarterUsesOnlyItsPointsAndLocalPlayingTime() {
    let value = analysis(events: [
      (1, 10, 2, 0), (1, 20, 2, 1),
      (2, 10, 2, 3), (2, 20, 3, 3), (2, 30, 3, 4),
    ])
    let quarter = ScoreDifferenceSeries(analysis: value, breakdown: .period(2))
    expectNoDifference(quarter.points.map(\.difference), [0, -2, -1, -2])
    expectNoDifference(quarter.moments.map(\.teamAScore), [0, 1, 1])
    expectNoDifference(quarter.moments.map(\.teamBScore), [2, 2, 3])
    expectNoDifference(quarter.points.map(\.elapsedSeconds), [0, 10, 20, 30])
    expectNoDifference(quarter.duration, 90)
    expectNoDifference(quarter.periodEndOffsets, [])
    expectNoDifference(
      ScoreDifferenceSeries(analysis: value).points.map(\.difference),
      [0, 2, 1, -1, 0, -1])
  }

  @Test func emptyQuarterDoesNotShowGoalsFromOtherQuarters() {
    let series = ScoreDifferenceSeries(
      analysis: analysis(events: [(1, 10, 2, 0)]), breakdown: .period(2))
    #expect(series.moments.isEmpty)
    expectNoDifference(series.points.map(\.difference), [0])
    expectNoDifference(series.duration, 90)
    expectNoDifference(series.extent, 1)
  }

  @Test func completedQuarterExtendsToItsOwnEnd() {
    var value = analysis(events: [(1, 10, 2, 0), (2, 10, 2, 3)])
    value.isComplete = true
    let series = ScoreDifferenceSeries(analysis: value, breakdown: .period(1))
    expectNoDifference(series.points.last?.elapsedSeconds, 60)
    expectNoDifference(series.points.last?.difference, 2)
    expectNoDifference(series.points.last?.period, 1)
  }

  @Test func periodOffsetsExcludeBreaksAndKeepLateGoalsAtBoundary() {
    var value = analysis(events: [(1, 60, 1, 0), (2, 0, 1, 2), (2, 20, 2, 2)])
    value.periods.reverse()
    let series = ScoreDifferenceSeries(analysis: value)
    expectNoDifference(series.duration, 150)
    expectNoDifference(series.periodEndOffsets, [60])
    expectNoDifference(series.moments.map(\.elapsedSeconds), [60, 60, 80])
    expectNoDifference(series.moments.map(\.periodElapsedSeconds), [60, 0, 20])
    expectNoDifference(series.nearestMoment(to: 60)?.difference, -1)
  }

  @Test func completedGameExtendsFinalMarginButLiveGameDoesNot() {
    let live = analysis(events: [(1, 10, 2, 0)])
    var completed = live
    completed.isComplete = true
    expectNoDifference(ScoreDifferenceSeries(analysis: live).points.last?.elapsedSeconds, 10)
    let series = ScoreDifferenceSeries(analysis: completed)
    expectNoDifference(series.points.last?.elapsedSeconds, 150)
    expectNoDifference(series.points.last?.difference, 2)
    expectNoDifference(series.moments.count, 1)
  }

  @Test func finalBoundaryGoalDoesNotNeedDuplicateEndpoint() {
    var completed = analysis(events: [(2, 90, 0, 2)])
    completed.isComplete = true
    let series = ScoreDifferenceSeries(analysis: completed)
    expectNoDifference(series.points.count, 2)
    expectNoDifference(series.points.last?.elapsedSeconds, 150)
  }

  @Test func emptyAndTiedGamesHaveUsableScale() {
    let empty = ScoreDifferenceSeries(analysis: GameAnalysis())
    expectNoDifference(empty.duration, 1)
    expectNoDifference(empty.extent, 1)
    expectNoDifference(empty.points.map(\.difference), [0])
    #expect(empty.moments.isEmpty)
    #expect(empty.nearestMoment(to: 0) == nil)
    let tied = ScoreDifferenceSeries(analysis: analysis(events: [(1, 10, 1, 1)]))
    expectNoDifference(tied.extent, 1)
    #expect(!tied.moments.isEmpty)
  }

  @Test(arguments: [true, false]) func oneSidedScaleIncludesBothSigns(teamA: Bool) {
    let series = ScoreDifferenceSeries(
      analysis: analysis(events: [
        (1, 10, teamA ? 4 : 0, teamA ? 0 : 4)
      ]))
    expectNoDifference(series.extent, 4)
    expectNoDifference(series.moments.last?.difference, teamA ? 4 : -4)
  }

  @Test func undoAndTeamPresentationChangesDoNotLeaveStaleSeries() {
    var value = analysis(events: [(1, 10, 2, 0), (1, 20, 2, 3)])
    let scored = ScoreDifferenceSeries(analysis: value)
    value.teamAName = "Renamed team"
    value.teamABibColorHex = "#FFFFFF"
    expectNoDifference(ScoreDifferenceSeries(analysis: value), scored)
    value.goalTimeline = analysis(events: [(1, 10, 2, 0)]).goalTimeline
    let undone = ScoreDifferenceSeries(analysis: value)
    expectNoDifference(undone.moments.map(\.difference), [2])
    expectNoDifference(undone.nearestMoment(to: 20)?.difference, 2)
  }

  private func analysis(events: [(period: Int, elapsed: Int, a: Int, b: Int)]) -> GameAnalysis {
    let gameID = UUID(0)
    let periods = [
      GamePeriod(
        id: UUID(1), gameID: gameID, position: 0, durationSeconds: 60,
        breakAfterDurationSeconds: 240),
      GamePeriod(id: UUID(2), gameID: gameID, position: 1, durationSeconds: 90),
    ]
    let goals = events.enumerated().map { index, event in
      let previousA = index > 0 ? events[index - 1].a : 0
      let previousB = index > 0 ? events[index - 1].b : 0
      let teamA = event.a > previousA
      return GoalTimelineItem(
        clockSecondsRemaining: periods[event.period - 1].durationSeconds - event.elapsed,
        id: UUID(index + 10), period: event.period,
        points: teamA ? event.a - previousA : event.b - previousB,
        scoringTeamName: "Team", scoringTeamSide: teamA ? .teamA : .teamB,
        teamAScore: event.a, teamBScore: event.b
      )
    }
    return GameAnalysis(
      goalTimeline: GoalTimeline(
        quarters: periods.reversed().map { period in
          GoalTimelineQuarter(
            goals: goals.filter { $0.period == period.number }.reversed(),
            period: period.number, teamAQuarterScore: 0, teamBQuarterScore: 0
          )
        }),
      periods: periods
    )
  }
}
