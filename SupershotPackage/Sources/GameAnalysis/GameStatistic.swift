import Database
import Foundation

package enum GameStatistic: String, CaseIterable, Identifiable {
  case centrePassConversion = "Centre pass conversion"
  case averageTimeToGoal = "Avg time to goal"
  case turnovers = "Turnovers"
  case biggestLead = "Biggest lead"
  case longestScoringRun = "Longest scoring run"

  package var id: Self {
    self
  }

  package func value(_ statistics: TeamGameStatistics) -> Double? {
    switch self {
    case .centrePassConversion:
      guard let centrePass = statistics.centrePass, centrePass.opportunities > 0 else { return nil }
      return Double(centrePass.conversions) / Double(centrePass.opportunities)
    case .averageTimeToGoal:
      return statistics.averageTimeToGoalSeconds
    case .turnovers:
      return statistics.centrePass.map { Double($0.inferredTurnovers) }
    case .biggestLead:
      return Double(statistics.biggestLead)
    case .longestScoringRun:
      return Double(statistics.longestScoringRun)
    }
  }

  package func text(_ statistics: TeamGameStatistics) -> String {
    guard let value = value(statistics) else { return "—" }
    switch self {
    case .centrePassConversion:
      guard let centrePass = statistics.centrePass else { return "—" }
      return
        "\(centrePass.conversions)/\(centrePass.opportunities) · \(Int((value * 100).rounded()))%"
    case .averageTimeToGoal:
      let seconds = max(Int(value.rounded()), 0)
      return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    case .turnovers:
      return "\(Int(value))"
    case .biggestLead:
      return "\(Int(value)) \(value == 1 ? "point" : "points")"
    case .longestScoringRun:
      return "\(Int(value)) \(value == 1 ? "goal" : "goals")"
    }
  }

  package func accessibleText(_ statistics: TeamGameStatistics) -> String {
    guard let value = value(statistics) else { return "unavailable" }
    if self == .averageTimeToGoal {
      let seconds = max(Int(value.rounded()), 0)
      return "\(seconds / 60) \(seconds / 60 == 1 ? "minute" : "minutes"), "
        + "\(seconds % 60) \(seconds % 60 == 1 ? "second" : "seconds")"
    }
    return text(statistics)
  }

  /// Relative magnitude, without assigning a better/worse interpretation to the metric.
  package func teamAFraction(
    teamA: TeamGameStatistics, teamB: TeamGameStatistics
  ) -> Double? {
    guard let a = value(teamA), let b = value(teamB),
          a.isFinite, b.isFinite, a >= 0, b >= 0, a + b > 0
    else { return nil }
    return a / (a + b)
  }
}
