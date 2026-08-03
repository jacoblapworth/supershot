import ComposableArchitecture
import CustomDump
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct TeamEditorFeatureTests {
    @Test
    func teamEditorTrimsAndPersistsNameAndColor() async throws {
      let team = Team(id: UUID(-1), name: "Ravens", colorHex: TeamColorPalette.blue)
      let store = TestStore(initialState: TeamEditorFeature.State(team: team)) {
        TeamEditorFeature()
      } withDependencies: {
        try! $0.bootstrapDatabase()
        try! clearDatabase($0.defaultDatabase)
        try! $0.defaultDatabase.write { db in
          try Team.insert { team }.execute(db)
        }
      }

      await store.send(.binding(.set(\.name, "  Falcons  "))) {
        $0.name = "  Falcons  "
      }
      await store.send(.paletteColorButtonTapped("#34c759")) {
        $0.colorHex = "#34C759"
      }
      await store.send(.saveButtonTapped) {
        $0.errorMessage = nil
        $0.isSaving = true
        $0.name = "Falcons"
      }
      await store.receive {
        guard case .saveResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.isSaving = false
      }
      await store.receive {
        guard case .delegate(.saved) = $0 else { return false }
        return true
      }

      let savedTeam = try await store.dependencies.defaultDatabase.read { db in
        try Team.find(team.id).fetchOne(db)
      }
      expectNoDifference(
        savedTeam,
        Team(id: team.id, name: "Falcons", colorHex: "#34C759")
      )
    }

    @Test
    func teamEditorCreatesNewTeam() async throws {
      let store = TestStore(initialState: TeamEditorFeature.State()) {
        TeamEditorFeature()
      } withDependencies: {
        $0.uuid = .incrementing
        try! $0.bootstrapDatabase()
        try! clearDatabase($0.defaultDatabase)
      }

      await store.send(.binding(.set(\.name, "  Falcons  "))) {
        $0.name = "  Falcons  "
      }
      await store.send(.paletteColorButtonTapped("#34c759")) {
        $0.colorHex = "#34C759"
      }
      await store.send(.saveButtonTapped) {
        $0.errorMessage = nil
        $0.isSaving = true
        $0.name = "Falcons"
      }
      await store.receive {
        guard case .saveResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.isSaving = false
      }
      await store.receive {
        guard case .delegate(.saved) = $0 else { return false }
        return true
      }

      let savedTeams = try await store.dependencies.defaultDatabase.read { db in
        try Team.fetchAll(db)
      }
      expectNoDifference(savedTeams.count, 1)
      expectNoDifference(savedTeams.first?.name, "Falcons")
      expectNoDifference(savedTeams.first?.colorHex, "#34C759")
    }

    @Test
    func teamEditorAllowsDuplicateNames() async throws {
      let ravens = Team(id: UUID(-1), name: "Ravens")
      let swifts = Team(id: UUID(-2), name: "Swifts")
      let store = TestStore(initialState: TeamEditorFeature.State(team: ravens)) {
        TeamEditorFeature()
      } withDependencies: {
        try! $0.bootstrapDatabase()
        try! clearDatabase($0.defaultDatabase)
        try! $0.defaultDatabase.write { db in
          try Team.insert {
            ravens
            swifts
          }
          .execute(db)
        }
      }

      await store.send(.binding(.set(\.name, "  SWIFTS "))) {
        $0.name = "  SWIFTS "
      }
      await store.send(.saveButtonTapped) {
        $0.errorMessage = nil
        $0.isSaving = true
        $0.name = "SWIFTS"
      }
      await store.receive {
        guard case .saveResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.isSaving = false
      }
      await store.receive {
        guard case .delegate(.saved) = $0 else { return false }
        return true
      }

      let savedTeam = try await store.dependencies.defaultDatabase.read { db in
        try Team.find(ravens.id).fetchOne(db)
      }
      expectNoDifference(savedTeam?.name, "SWIFTS")
    }

    @Test
    func teamEditorReportsWhenTeamWasDeleted() async {
      let team = Team(id: UUID(-1), name: "Ravens")
      let store = TestStore(initialState: TeamEditorFeature.State(team: team)) {
        TeamEditorFeature()
      } withDependencies: {
        try! $0.bootstrapDatabase()
        try! clearDatabase($0.defaultDatabase)
      }

      await store.send(.binding(.set(\.name, "Falcons"))) {
        $0.name = "Falcons"
      }
      await store.send(.saveButtonTapped) {
        $0.errorMessage = nil
        $0.isSaving = true
      }
      await store.receive {
        guard case .saveResponse(.failure) = $0 else { return false }
        return true
      } assert: {
        $0.errorMessage = "This team is no longer available."
        $0.isSaving = false
      }
    }
  }
}
