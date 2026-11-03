import ComposableArchitecture
import CustomDump
@testable import Database
import Dependencies
import Foundation
import GameCore
import SQLiteData
@testable import TeamEditingFeature
import Testing
import TestSupport

extension SupershotTestSuite {
  @MainActor
  struct TeamFavoriteFeatureTests {
    @Test
    func favoriteAndUnfavoritePersistWithoutChangingTheTeam() async throws {
      let team = Team(id: UUID(71), name: "Ravens", logoData: Data([1, 2]))
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      try await database.write { db in try Team.insert { team }.execute(db) }
      let store = TestStore(initialState: TeamFavoriteFeature.State()) {
        TeamFavoriteFeature()
      }
      for wasFavorite in [false, true] {
        await store.send(.favoriteButtonTapped(team.id, isFavorite: wasFavorite)) {
          $0.savingTeamIDs = [team.id]
        }
        await store.receive(\.saveResponse) {
          $0.savingTeamIDs = []
        }
        let value = try await database.read { db in
          try (Team.find(team.id).fetchOne(db), TeamDetailRequest(teamID: team.id).fetch(db))
        }
        expectNoDifference(value.0, team)
        #expect(value.1.isFavorite == !wasFavorite)
      }
    }

    @Test
    func deletedTeamFailsWithoutRecreatingItAndAllowsRetry() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let id = UUID(71)
      let store = TestStore(initialState: TeamFavoriteFeature.State()) {
        TeamFavoriteFeature()
      }
      store.exhaustivity = .off
      await store.send(.favoriteButtonTapped(id, isFavorite: false))
      await store.receive(\.saveResponse)
      #expect(store.state.alert != nil)
      #expect(store.state.savingTeamIDs.isEmpty)
      #expect(try await database.read { db in try Team.fetchCount(db) } == 0)
      #expect(try await database.read { db in try TeamFavorite.fetchCount(db) } == 0)
      await store.send(.alert(.dismiss))
      try await database.write { db in
        try Team.insert { Team(id: id, name: "Ravens") }.execute(db)
      }
      await store.send(.favoriteButtonTapped(id, isFavorite: false))
      await store.receive(\.saveResponse)
      #expect(try await database.read { db in try TeamFavorite.fetchCount(db) } == 1)
    }

    @Test
    func pickerLoadsFavoritesFirstWhileKeepingSearchAndExclusions() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let aces = Team(id: UUID(71), name: "Aces")
      let ravens = Team(id: UUID(72), name: "Rávéns")
      let swifts = Team(id: UUID(73), name: "Swifts")
      try await database.write { db in
        try Team.insert { aces; ravens; swifts }.execute(db)
        try TeamFavorite.setFavorite(true, teamID: swifts.id, in: db)
        try TeamFavorite.setFavorite(true, teamID: ravens.id, in: db)
      }
      let store = TestStore(initialState: TeamPickerFeature.State(excluding: [swifts.id])) {
        TeamPickerFeature()
      }
      await store.send(.task) {
        $0.didLoadTeams = true
        $0.isLoadingTeams = true
      }
      await store.receive(\.teamsResponse) {
        $0.isLoadingTeams = false
        $0.availableTeams = [ravens, swifts, aces]
        $0.favoriteIDs = [ravens.id, swifts.id]
      }
      expectNoDifference(store.state.filteredTeams, [ravens, aces])
      await store.send(.binding(.allCasePaths.searchText.embed("ravens"))) { $0.searchText = "ravens" }
      expectNoDifference(store.state.filteredTeams, [ravens])
      await store.send(.binding(.allCasePaths.searchText.embed("aces"))) { $0.searchText = "aces" }
      expectNoDifference(store.state.filteredTeams, [aces])
    }
  }
}
