import Database

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

  package var title: String {
    switch self {
    case .wholeGame: "Game"
    case let .period(period): "Q\(period)"
    }
  }

  package func statistics(in analysis: GameAnalysis) -> CompletedGameStatistics {
    guard let period else { return analysis.statistics }
    return analysis.statisticsByPeriod[period] ?? CompletedGameStatistics()
  }
}
