import DependenciesTestSupport
import GRDB
import SQLiteData
import Testing

@testable import Supershot

@Suite(
  .serialized,
  .dependencies {
    try $0.bootstrapDatabase()
  }
)
struct SupershotTestSuite {}

nonisolated func clearDatabase(_ database: any DatabaseWriter) throws {
  try database.write { db in
    try Goal.delete().execute(db)
    try Game.delete().execute(db)
    try Team.delete().execute(db)
  }
}
