import CoreGraphics
@testable import Database
import Dependencies
import Foundation
import GameCore
import GRDB
import ImageIO
import SQLiteData
import Testing
import TestSupport
import UniformTypeIdentifiers
import WidgetSupport

extension SupershotTestSuite {
  @MainActor
  struct GamesWidgetObservationTests {
    @Test func committedChangesPublishAndReloadSnapshot() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: url) }
      let (updates, continuation) = AsyncStream<Void>.makeStream()
      let observation = GamesWidgetObservation(database: database, snapshotURL: url) {
        continuation.yield(())
      }
      defer { withExtendedLifetime(observation) {}; continuation.finish() }
      var iterator = updates.makeAsyncIterator()
      _ = await iterator.next()
      #expect(try GamesWidgetStore.read(from: url).isEmpty)
      let gameID = UUID(3)
      try await database.write { db in
        try db.seed {
          Team(id: UUID(1), name: "A")
          Team(id: UUID(2), name: "B")
          Game(id: gameID, startedAt: nil, teamAID: UUID(1), teamBID: UUID(2))
        }
        try GamePeriod.insert { testGamePeriods(gameID: gameID) }.execute(db)
      }
      _ = await iterator.next()
      #expect(try GamesWidgetStore.read(from: url).first?.isPlanned == true)
      try await database.write { db in
        try Team.find(UUID(1)).update { $0.name = "Updated" }.execute(db)
        try Game.find(gameID).update { $0.startedAt = #bind(Date()) }.execute(db)
        try Goal.insert {
          Goal(
            id: UUID(4),
            gameID: gameID,
            gamePeriodID: testGamePeriodID(gameID: gameID, position: 0),
            teamID: UUID(1),
            elapsedSeconds: 1,
            points: 2,
            createdAt: Date()
          )
        }.execute(db)
      }
      _ = await iterator.next()
      let updated = try #require(GamesWidgetStore.read(from: url).first)
      #expect(updated.teamAName == "Updated")
      #expect(updated.teamAScore == 2)
      #expect(!updated.isPlanned)
      let logo = try transparentLogo()
      try await database.write { db in
        try Team.find(UUID(1)).update { $0.logoData = #bind(logo) }.execute(db)
      }
      _ = await iterator.next()
      let gameWithLogo = try #require(GamesWidgetStore.read(from: url).first)
      let thumbnailData = try #require(gameWithLogo.teamALogoData)
      let source = try #require(CGImageSourceCreateWithData(thumbnailData as CFData, nil))
      let thumbnail = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
      #expect(thumbnail.width == 128)
      #expect(thumbnail.height == 64)
      #expect(thumbnail.alphaInfo == .first || thumbnail.alphaInfo == .last
        || thumbnail.alphaInfo == .premultipliedFirst || thumbnail.alphaInfo == .premultipliedLast)
      #expect(gameWithLogo.teamBLogoData == nil)

      try await database.write { db in
        try Game.find(gameID).update { $0.endedAt = #bind(Date()) }.execute(db)
      }
      _ = await iterator.next()
      #expect(try GamesWidgetStore.read(from: url).first?.isCompleted == true)
      try await database.write { db in try Game.find(gameID).delete().execute(db) }
      _ = await iterator.next()
      #expect(try GamesWidgetStore.read(from: url).isEmpty)
    }

    private func transparentLogo() throws -> Data {
      let rgba = CGColorSpaceCreateDeviceRGB()
      let context = try #require(CGContext(
        data: nil,
        width: 256,
        height: 128,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: rgba,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ))
      context.clear(CGRect(x: 0, y: 0, width: 256, height: 128))
      let image = try #require(context.makeImage())
      let data = NSMutableData()
      let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
      CGImageDestinationAddImage(destination, image, nil)
      try #require(CGImageDestinationFinalize(destination))
      return data as Data
    }
  }
}
