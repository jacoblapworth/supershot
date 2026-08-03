import CustomDump
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct TeamIdentityFeatureTests {
    @Test
    func teamIdentityTrimsNameAndCanonicalizesColor() {
      let team = Team(id: UUID(50), name: "  E\u{301}CLAIRS  ", colorHex: "#abcdef")

      expectNoDifference(team.name, "E\u{301}CLAIRS")
      expectNoDifference(team.colorHex, "#ABCDEF")
    }

    @Test
    func teamProfilesAllowDuplicateNames() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)

      try await database.write { db in
        try Team.insert {
          Team(id: UUID(51), name: "Éclairs")
          Team(id: UUID(52), name: "  E\u{301}CLAIRS ")
        }.execute(db)
      }

      let teams = try await database.read { db in
        try Team.fetchAll(db)
      }
      expectNoDifference(teams.map(\.id), [UUID(51), UUID(52)])
    }
  }
}
