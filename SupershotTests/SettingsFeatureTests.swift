import ComposableArchitecture
import Foundation
import SQLiteData
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct SettingsFeatureTests {
#if DEBUG
    @Test
    func databaseExportPresentsSnapshotAndCanBeCancelled() async {
      let url = URL(filePath: "/tmp/Supershot.sqlite")
      let removedURLs = LockIsolated<[URL]>([])
      let store = TestStore(initialState: SettingsFeature.State()) {
        SettingsFeature()
      } withDependencies: {
        $0[DatabaseExportClient.self].snapshot = { url }
        $0[DatabaseExportClient.self].removeSnapshot = { url in
          removedURLs.withValue { $0.append(url) }
        }
      }

      await store.send(.exportDatabaseButtonTapped) {
        $0.databaseExport = .preparing
      }
      await store.receive(\.databaseExportResponse.success) {
        $0.databaseExport = .ready(url)
      }
      #expect(store.state.isDatabaseSharePresented)
      #expect(removedURLs.value.isEmpty)
      await store.send(.databaseSharePresentationChanged(false)) {
        $0.databaseExport = nil
      }
      #expect(!store.state.isDatabaseSharePresented)
      await store.finish()
      #expect(removedURLs.value == [url])
    }

    @Test
    func databaseExportIgnoresRepeatedTapsWhilePreparing() async {
      var state = SettingsFeature.State()
      state.databaseExport = .preparing
      let store = TestStore(initialState: state) {
        SettingsFeature()
      }
      await store.send(.exportDatabaseButtonTapped)
    }

    @Test
    func databaseExportFailureAllowsRetry() async {
      let error = CocoaError(.fileWriteNoPermission)
      let store = TestStore(initialState: SettingsFeature.State()) {
        SettingsFeature()
      } withDependencies: {
        $0[DatabaseExportClient.self].snapshot = { throw error }
      }

      await store.send(.exportDatabaseButtonTapped) {
        $0.databaseExport = .preparing
      }
      await store.receive(\.databaseExportResponse.failure) {
        $0.databaseExport = nil
        $0.alert = .databaseExportFailed(error)
      }
      await store.send(.alert(.dismiss)) {
        $0.alert = nil
      }
      store.dependencies[DatabaseExportClient.self].snapshot = { URL(filePath: "/tmp/Supershot.sqlite") }
      await store.send(.exportDatabaseButtonTapped) {
        $0.databaseExport = .preparing
      }
      await store.receive(\.databaseExportResponse.success) {
        $0.databaseExport = .ready(URL(filePath: "/tmp/Supershot.sqlite"))
      }
      await store.send(.databaseShareCompleted(.success(()))) {
        $0.databaseExport = nil
      }
      await store.finish()
    }

    @Test
    func databaseShareFailureIsPresented() async {
      var state = SettingsFeature.State()
      state.databaseExport = .ready(URL(filePath: "/tmp/Supershot.sqlite"))
      let error = CocoaError(.fileWriteOutOfSpace)
      let store = TestStore(initialState: state) {
        SettingsFeature()
      }
      await store.send(.databaseShareCompleted(.failure(error))) {
        $0.databaseExport = nil
        $0.alert = .databaseExportFailed(error)
      }
      await store.finish()
    }

    @Test
    func databaseSnapshotIncludesUncheckpointedWrites() async throws {
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let sourceURL = directory.appendingPathComponent("source.sqlite")
      let source = try DatabasePool(path: sourceURL.path)
      try await source.write { db in
        try db.execute(sql: "PRAGMA wal_autocheckpoint = 0")
        try db.execute(sql: "CREATE TABLE inspection (value TEXT NOT NULL)")
        try db.execute(sql: "INSERT INTO inspection VALUES ('Latest goal')")
      }
      #expect(FileManager.default.fileExists(atPath: sourceURL.path + "-wal"))
      let exportURL = try await withDependencies {
        $0.defaultDatabase = source
        $0.uuid = .incrementing
      } operation: {
        try await DatabaseExportClient.liveValue.snapshot()
      }
      defer { DatabaseExportClient.liveValue.removeSnapshot(exportURL) }
      #expect(exportURL.lastPathComponent == "Supershot.sqlite")
      let exported = try DatabaseQueue(path: exportURL.path)
      let value = try await exported.read { db in
        try String.fetchOne(db, sql: "SELECT value FROM inspection")
      }
      #expect(value == "Latest goal")
      let integrity = try await exported.read { db in
        try String.fetchOne(db, sql: "PRAGMA integrity_check")
      }
      #expect(integrity == "ok")
      try await source.write { db in
        try db.execute(sql: "INSERT INTO inspection VALUES ('Another goal')")
      }
      let count = try await exported.read { db in
        try Int.fetchOne(db, sql: "SELECT count(*) FROM inspection")
      }
      #expect(count == 1)
      try exported.close()
      try source.close()
      DatabaseExportClient.liveValue.removeSnapshot(exportURL)
      #expect(!FileManager.default.fileExists(atPath: exportURL.path))
    }
#endif
    @Test
    func customerCenterPresentationIsFeatureOwned() async {
      let store = TestStore(initialState: SettingsFeature.State()) {
        SettingsFeature()
      }

      await store.send(.manageSubscriptionButtonTapped) {
        $0.isCustomerCenterPresented = true
      }
      await store.send(.customerCenterPresentationChanged(false)) {
        $0.isCustomerCenterPresented = false
      }
    }

    @Test
    func subscriptionActionsDelegateToApp() async {
      let store = TestStore(initialState: SettingsFeature.State()) {
        SettingsFeature()
      }

      await store.send(.proPromotionTapped)
      await store.receive {
        guard case .delegate(.proPromotionTapped) = $0 else { return false }
        return true
      }

      await store.send(.customerInfoUpdated(.pro))
      await store.receive {
        guard case .delegate(.proAccessChanged(.pro)) = $0 else { return false }
        return true
      }
    }
  }
}
