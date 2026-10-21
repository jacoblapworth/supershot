import Database
import Dependencies
import DependenciesTestSupport
import Foundation
import GameServices
import Testing

@Suite(
  .serialized,
  .dependencies {
    $0.uuid = .incrementing
    $0.date.now = Date(timeIntervalSince1970: 1_000)
    try $0.bootstrapDatabase()
    $0.gameScoring = .live
    $0.gameSession = .live
    $0.gameTimer = .live
    $0.gamePresentation = .live
  }
)
struct SupershotTestSuite {}
