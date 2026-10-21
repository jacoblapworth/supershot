import CryptoKit
import Database
import DependenciesTestSupport
import Foundation
import GameCore
import GameServices
import GRDB
import SharedModels
import SQLiteData
import Testing

@Suite(
  .serialized,
  .dependencies {
    try $0.bootstrapDatabase()
    $0.gameScoring = .live
    $0.gameSession = .live
    $0.gameTimer = .live
    $0.gamePresentation = .live
  }
)
struct SupershotTestSuite {}
