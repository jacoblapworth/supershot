import Foundation
@testable import Supershot
import Testing

@MainActor
struct GameActivityManagerTests {
  private final class Activity {
    let id: String
    let gameID: UUID
    var reusable = true
    var updates: [Int] = []
    var ends = 0

    init(_ id: String, gameID: UUID) {
      self.id = id
      self.gameID = gameID
    }
  }

  private func manager(
    activities: @escaping () -> [Activity],
    update: ((Activity, Int) async -> Void)? = nil
  ) -> GameActivityManager<Activity, Int> {
    GameActivityManager(
      activities: activities,
      id: { $0.id },
      gameID: { $0.gameID },
      isReusable: { $0.reusable },
      update: update ?? { $0.updates.append($1) },
      end: { $0.ends += 1; $0.reusable = false }
    )
  }

  @Test func relaunchReusesExistingActivityAndRemovesDuplicates() async {
    let gameID = UUID()
    let first = Activity("1", gameID: gameID)
    let duplicate = Activity("2", gameID: gameID)
    let other = Activity("3", gameID: UUID())
    let manager = manager { [duplicate, other, first] }
    await manager.update(gameID: gameID, content: 42) {
      Issue.record("Restoring a game must not request another activity")
      return nil
    }
    #expect(first.updates == [42])
    #expect(duplicate.ends == 1)
    #expect(other.ends == 0)
  }

  @Test func overlappingUpdatesReuseRequestBeforeSystemListCatchesUp() async {
    let gameID = UUID()
    let activity = Activity("1", gameID: gameID)
    var requests = 0
    var suspendedUpdate: CheckedContinuation<Void, Never>?
    let manager = manager(activities: { [] }, update: { activity, content in
      activity.updates.append(content)
      if content == 1 {
        await withCheckedContinuation { suspendedUpdate = $0 }
      }
    })
    let first = Task { @MainActor in
      await manager.update(gameID: gameID, content: 1) {
        requests += 1
        return activity
      }
    }
    while suspendedUpdate == nil {
      await Task.yield()
    }
    await manager.update(gameID: gameID, content: 2) {
      requests += 1
      return Activity("2", gameID: gameID)
    }
    suspendedUpdate?.resume()
    await first.value
    #expect(requests == 1)
    #expect(activity.updates == [1, 2])
    await manager.end(gameID: gameID)
    #expect(activity.ends == 1)
  }

  @Test func reconciliationRemovesOrphansAndDuplicatesWithoutStartingActivities() async {
    let gameID = UUID()
    let first = Activity("1", gameID: gameID)
    let duplicate = Activity("2", gameID: gameID)
    let orphan = Activity("3", gameID: UUID())
    let ended = Activity("4", gameID: gameID)
    ended.reusable = false
    let manager = manager { [orphan, duplicate, ended, first] }
    await manager.reconcile(keeping: [gameID])
    #expect(first.ends == 0)
    #expect(duplicate.ends == 1)
    #expect(orphan.ends == 1)
    #expect(ended.ends == 1)
    await manager.reconcile(keeping: [])
    #expect(first.ends == 1)
  }

  @Test func staleActivityIsReusedAndEndedActivityIsReplaced() async {
    let gameID = UUID()
    let stale = Activity("1", gameID: gameID)
    let manager = manager { [stale] }
    await manager.update(gameID: gameID, content: 1) { nil }
    #expect(stale.updates == [1])
    stale.reusable = false
    let replacement = Activity("2", gameID: gameID)
    await manager.update(gameID: gameID, content: 2) { replacement }
    #expect(stale.ends == 1)
    #expect(replacement.updates == [2])
  }

  @Test func failedRequestCanBeRetried() async {
    let gameID = UUID()
    let manager = manager { [] }
    await manager.update(gameID: gameID, content: 1) { nil }
    let activity = Activity("1", gameID: gameID)
    await manager.update(gameID: gameID, content: 2) { activity }
    #expect(activity.updates == [2])
  }
}
