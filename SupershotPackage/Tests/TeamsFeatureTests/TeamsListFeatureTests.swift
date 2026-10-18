import SwiftUI
import CustomDump
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

import TestSupport
@testable import AlarmClient
@testable import AppSettings
@testable import Database
@testable import GameAnalysis
@testable import GameCore
@testable import GameDetailFeature
@testable import GameServices
@testable import LocationClient
@testable import NewGameFeature
@testable import PaywallFeature
@testable import PermissionsFeature
@testable import PreviewSupport
@testable import ScoringFeature
@testable import SharedModels
@testable import SoundEffectsClient
@testable import Styleguide
@testable import SubscriptionClient
@testable import TeamEditingFeature
@testable import TeamsFeature
@testable import WidgetSupport

extension SupershotTestSuite {
  @MainActor
  @Suite struct TeamsListFeatureTests {
    @Test
    func teamsListIsAlphabeticalWithGameCounts() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)

      try await database.write { db in
        try db.seed {
          Team(id: UUID(-1), name: "Ravens", colorHex: ColorPalette.blue.hex())
          Team(id: UUID(-2), name: "Swifts", colorHex: ColorPalette.red.hex())
          Team(id: UUID(-3), name: "Aces", colorHex: "#34C759")
          Game(
            id: UUID(-1),
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: nil,
            teamAID: UUID(-1),
            teamBID: UUID(-2)
          )
          Game(
            id: UUID(-2),
            startedAt: Date(timeIntervalSince1970: 2_000),
            endedAt: Date(timeIntervalSince1970: 3_000),
            teamAID: UUID(-3),
            teamBID: UUID(-1)
          )
        }
      }

      let value = try await database.read { db in
        try TeamsRequest().fetch(db)
      }

      expectNoDifference(
        value.teams,
        [
          TeamListItem(
            color: Color(hex: "#34C759"),
            gameCount: 1,
            id: UUID(-3),
            name: "Aces"
          ),
          TeamListItem(
            color: ColorPalette.blue,
            gameCount: 2,
            id: UUID(-1),
            name: "Ravens"
          ),
          TeamListItem(
            color: ColorPalette.red,
            gameCount: 1,
            id: UUID(-2),
            name: "Swifts"
          ),
        ]
      )
    }
  }
}
