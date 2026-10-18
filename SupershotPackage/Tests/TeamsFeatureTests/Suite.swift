import DependenciesTestSupport
import Database
import GameServices
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
