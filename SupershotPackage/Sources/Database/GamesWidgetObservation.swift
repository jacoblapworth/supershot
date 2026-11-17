import Dependencies
import Foundation
import GRDB
import ImageIO
import OSLog
import SQLiteData
import UniformTypeIdentifiers
import WidgetKit
import WidgetSupport

package extension GameListItem {
  nonisolated var widgetGame: WidgetGame {
    WidgetGame(
      id: id,
      createdAt: createdAt,
      scheduledAt: scheduledAt,
      startedAt: startedAt,
      endedAt: endedAt,
      court: court,
      period: currentQuarter,
      teamAName: teamAName,
      teamAColorHex: teamABibColorHex,
      teamAScore: teamAScore,
      teamBName: teamBName,
      teamBColorHex: teamBBibColorHex,
      teamBScore: teamBScore,
      teamALogoData: Self.widgetLogoThumbnail(teamALogoData),
      teamBLogoData: Self.widgetLogoThumbnail(teamBLogoData)
    )
  }

  private nonisolated static func widgetLogoThumbnail(_ data: Data?) -> Data? {
    guard let data,
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 128,
          ] as CFDictionary)
    else { return nil }

    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, thumbnail, nil)
    return CGImageDestinationFinalize(destination) ? output as Data : nil
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
