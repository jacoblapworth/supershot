import Foundation

/// Retains newly requested activities before ActivityKit's activities list catches up.
/// Selection and creation happen on the main actor without suspending.
@MainActor
final class GameActivityManager<Activity, Content> {
  private var retained: [UUID: Activity] = [:]
  private let activities: () -> [Activity]
  private let id: (Activity) -> String
  private let gameID: (Activity) -> UUID
  private let isReusable: (Activity) -> Bool
  private let update: (Activity, Content) async -> Void
  private let end: (Activity) async -> Void

  init(
    activities: @escaping () -> [Activity],
    id: @escaping (Activity) -> String,
    gameID: @escaping (Activity) -> UUID,
    isReusable: @escaping (Activity) -> Bool,
    update: @escaping (Activity, Content) async -> Void,
    end: @escaping (Activity) async -> Void
  ) {
    self.activities = activities
    self.id = id
    self.gameID = gameID
    self.isReusable = isReusable
    self.update = update
    self.end = end
  }

  func update(gameID: UUID, content: Content, create: () -> Activity?) async {
    let matches = knownActivities().filter { self.gameID($0) == gameID }
    let activity = matches.first(where: isReusable) ?? create()
    // Store before the first await so a concurrent caller reuses the same request.
    retained[gameID] = activity
    for duplicate in matches where activity.map({ id($0) != id(duplicate) }) ?? true {
      await end(duplicate)
    }
    if let activity {
      await update(activity, content)
    }
  }

  func reconcile(keeping gameIDs: Set<UUID>) async {
    var keep: [UUID: Activity] = [:]
    var removed: [Activity] = []
    for activity in knownActivities() {
      let gameID = gameID(activity)
      if gameIDs.contains(gameID), isReusable(activity), keep[gameID] == nil {
        keep[gameID] = activity
      } else {
        removed.append(activity)
      }
    }
    retained = keep
    for activity in removed {
      await end(activity)
    }
  }

  func end(gameID: UUID) async {
    let matches = knownActivities().filter { self.gameID($0) == gameID }
    retained[gameID] = nil
    for activity in matches {
      await end(activity)
    }
  }

  private func knownActivities() -> [Activity] {
    var seen: Set<String> = []
    // Prefer retained instances, then use a stable order when restoring after launch.
    return (retained.values.sorted { id($0) < id($1) } + activities().sorted { id($0) < id($1) })
      .filter { seen.insert(id($0)).inserted }
  }
}
