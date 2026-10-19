import Database
import GameCore

/// Quarter scores start at zero; the selected breakdown's winner is plotted above zero.
nonisolated package struct ScoreDifferenceSeries: Equatable, Sendable {
  package struct Point: Equatable, Identifiable, Sendable {
    package enum ID: Hashable, Sendable {
      case start
      case goal(Goal.ID)
      case end
    }

    package let id: ID
    package let elapsedSeconds: Int
    package let period: Int
    package let periodElapsedSeconds: Int
    package let teamAScore: Int
    package let teamBScore: Int

    package var difference: Int { teamAScore - teamBScore }
  }

  package let points: [Point]
  package let moments: [Point]
  package let duration: Int
  package let periodEndOffsets: [Int]
  package let extent: Int
  package let positiveTeamIsTeamA: Bool

  package init(analysis: GameAnalysis, breakdown: GameAnalysisBreakdown = .wholeGame) {
    let periods = analysis.periods
      .filter { breakdown.period == nil || $0.number == breakdown.period }
      .sorted { $0.position < $1.position }
    var offsets: [Int: Int] = [:]
    var duration = 0
    var boundaries: [Int] = []
    for period in periods {
      offsets[period.number] = duration
      duration += period.durationSeconds
      boundaries.append(duration)
    }
    self.duration = max(duration, 1)
    self.periodEndOffsets = Array(boundaries.dropLast())

    // Timeline presentation is newest first, including its same-second tie breaks.
    var teamAScore = 0
    var teamBScore = 0
    let moments = analysis.goalTimeline.quarters
      .filter { breakdown.period == nil || $0.period == breakdown.period }
      .reversed().flatMap { quarter in
        quarter.goals.reversed().compactMap { goal -> Point? in
          guard let period = periods.first(where: { $0.number == goal.period }),
            let offset = offsets[goal.period]
          else { return nil }
          let elapsed = min(
            max(period.durationSeconds - goal.clockSecondsRemaining, 0),
            period.durationSeconds)
          if breakdown == .wholeGame {
            teamAScore = goal.teamAScore
            teamBScore = goal.teamBScore
          } else {
            switch goal.scoringTeamSide {
            case .teamA: teamAScore += goal.points
            case .teamB: teamBScore += goal.points
            case .unknown: break
            }
          }
          return Point(
            id: .goal(goal.id), elapsedSeconds: offset + elapsed,
            period: goal.period, periodElapsedSeconds: elapsed,
            teamAScore: teamAScore, teamBScore: teamBScore
          )
        }
      }
    self.moments = moments
    // A tie has no winner, so keep a deterministic Team A reference.
    self.positiveTeamIsTeamA = (moments.last?.difference ?? 0) >= 0
    var points =
      [
        Point(
          id: .start, elapsedSeconds: 0, period: periods.first?.number ?? 1,
          periodElapsedSeconds: 0, teamAScore: 0, teamBScore: 0
        )
      ] + moments

    // Finishing is only allowed once the final playing period is complete.
    // Live games stop at the last goal rather than projecting a lead into the future.
    if analysis.isComplete, let last = moments.last, let period = periods.last,
      last.elapsedSeconds < duration
    {
      points.append(
        Point(
          id: .end, elapsedSeconds: duration, period: period.number,
          periodElapsedSeconds: period.durationSeconds,
          teamAScore: last.teamAScore, teamBScore: last.teamBScore
        ))
    }
    self.points = points
    self.extent = max(moments.map { abs($0.difference) }.max() ?? 0, 1)
  }

  package func nearestMoment(to elapsedSeconds: Int) -> Point? {
    // At a shared timestamp, inspect the score after its final scoring event.
    moments.reversed().min {
      abs($0.elapsedSeconds - elapsedSeconds) < abs($1.elapsedSeconds - elapsedSeconds)
    }
  }

  package func plottedDifference(for point: Point) -> Int {
    positiveTeamIsTeamA ? point.difference : -point.difference
  }
}
