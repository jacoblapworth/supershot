import Database
import SharedModels

package nonisolated enum GameAnalysisBreakdown: Hashable, Identifiable, Sendable {
  case wholeGame
  case period(Int)

  package var id: Self {
    self
  }

  package var period: Int? {
    guard case let .period(period) = self else { return nil }
    return period
  }

  package func title(periodCount: Int) -> String {
    switch self {
    case .wholeGame: "Game"
    case let .period(period): "\(GamePeriodFormat.abbreviation(for: periodCount))\(period)"
    }
  }

  package func statistics(in analysis: GameAnalysis) -> CompletedGameStatistics {
    guard let period else { return analysis.statistics }
    return analysis.statisticsByPeriod[period] ?? CompletedGameStatistics()
  }
}
