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
    func teamIdentityUsesStableUnicodeNormalizationAndCanonicalColor() {
      let team = Team(id: UUID(50), name: "  E\u{301}CLAIRS  ", colorHex: "#abcdef")

      expectNoDifference(team.name, "E\u{301}CLAIRS")
      expectNoDifference(team.normalizedName, "éclairs")
      expectNoDifference(team.colorHex, "#ABCDEF")
      expectNoDifference(Team.normalizeName("Éclairs"), team.normalizedName)
    }

    @Test
    func normalizedTeamNameIndexRejectsDuplicateProfiles() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)

      try await database.write { db in
        try Team.insert {
          Team(id: UUID(51), name: "Éclairs")
        }
        .execute(db)
      }

      do {
        try await database.write { db in
          try Team.insert {
            Team(id: UUID(52), name: "  E\u{301}CLAIRS ")
          }
          .execute(db)
        }
        Issue.record("Expected normalized team names to be unique")
      } catch {
        // The unique index is the final transactional guard against concurrent duplicates.
      }

      let teams = try await database.read { db in
        try Team.fetchAll(db)
      }
      expectNoDifference(teams.map(\.id), [UUID(51)])
    }
  }
}
