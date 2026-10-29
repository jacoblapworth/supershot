import Dependencies
import Foundation
import GRDB
import OSLog
import SQLiteData
import WidgetKit
import WidgetSupport

extension GameListItem {
  package var widgetGame: WidgetGame {
    WidgetGame(
      id: id, createdAt: createdAt, scheduledAt: scheduledAt, startedAt: startedAt,
      endedAt: endedAt, court: court, period: currentQuarter,
      teamAName: teamAName, teamAColorHex: teamABibColorHex, teamAScore: teamAScore,
      teamBName: teamBName, teamBColorHex: teamBBibColorHex, teamBScore: teamBScore
    )
  }
}

/// Retained for the app process, covering every committed change, including sync writes.
public final class GamesWidgetObservation {
  private var observation: AnyDatabaseCancellable?

  public convenience init() {
    @Dependency(\.defaultDatabase) var database
    self.init(database: database)
  }

  package init(
    database: any DatabaseReader,
    snapshotURL: URL? = nil,
    reload: @escaping @Sendable () -> Void = {
      WidgetCenter.shared.reloadTimelines(ofKind: GamesWidgetStore.kind)
    }
  ) {
    observation = ValueObservation.tracking { db in
      try GamesRequest().fetch(db).games.map(\.widgetGame)
    }
    .removeDuplicates()
    .start(in: database, onError: { error in
      Self.logger.error("Games widget observation failed: \(error)")
    }, onChange: { games in
      do {
        try GamesWidgetStore.write(games, to: snapshotURL)
        reload()
      } catch {
        Self.logger.error("Games widget snapshot failed: \(error)")
      }
    })
  }

  private nonisolated static let logger = Logger(subsystem: "Supershot", category: "GamesWidget")
}
