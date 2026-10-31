import Foundation

/// A versioned, read-only projection. The widget never opens or migrates the app database.
public nonisolated struct WidgetGame: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var createdAt: Date
  public var scheduledAt: Date?
  public var startedAt: Date?
  public var endedAt: Date?
  public var court: String?
  public var period: Int
  public var teamAName: String
  public var teamAColorHex: String
  public var teamAScore: Int
  public var teamBName: String
  public var teamBColorHex: String
  public var teamBScore: Int

  public var isPlanned: Bool {
    startedAt == nil && endedAt == nil
  }

  public var isCompleted: Bool {
    endedAt != nil
  }

  public init(
    id: UUID, createdAt: Date, scheduledAt: Date? = nil, startedAt: Date? = nil,
    endedAt: Date? = nil, court: String? = nil, period: Int = 1,
    teamAName: String, teamAColorHex: String, teamAScore: Int = 0,
    teamBName: String, teamBColorHex: String, teamBScore: Int = 0
  ) {
    self.id = id
    self.createdAt = createdAt
    self.scheduledAt = scheduledAt
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.court = court
    self.period = period
    self.teamAName = teamAName
    self.teamAColorHex = teamAColorHex
    self.teamAScore = teamAScore
    self.teamBName = teamBName
    self.teamBColorHex = teamBColorHex
    self.teamBScore = teamBScore
  }
}

public nonisolated enum GamesWidgetSelection {
  public static let recentHistory: TimeInterval = 7 * 24 * 60 * 60
  public static let overdueAllowance: TimeInterval = 24 * 60 * 60

  public static func games(_ games: [WidgetGame], at now: Date) -> [WidgetGame] {
    func priority(_ game: WidgetGame) -> Int {
      if game.isPlanned {
        guard let date = game.scheduledAt else { return 4 }
        return now.timeIntervalSince(date) <= overdueAllowance ? 0 : 3
      }
      return game.isCompleted ? 2 : 1
    }
    return games.filter {
      guard let endedAt = $0.endedAt else { return true }
      return now.timeIntervalSince(endedAt) <= recentHistory
    }.sorted { lhs, rhs in
      let group = priority(lhs)
      if group != priority(rhs) {
        return group < priority(rhs)
      }
      let left = lhs.scheduledAt ?? lhs.createdAt
      let right = rhs.scheduledAt ?? rhs.createdAt
      switch group {
      case 0, 3:
        if left != right {
          return left < right
        }
      case 1:
        if lhs.startedAt != rhs.startedAt {
          return (lhs.startedAt ?? .distantPast) < (rhs.startedAt ?? .distantPast)
        }
      case 2:
        if lhs.endedAt != rhs.endedAt {
          return (lhs.endedAt ?? .distantPast) > (rhs.endedAt ?? .distantPast)
        }
      default:
        if lhs.createdAt != rhs.createdAt {
          return lhs.createdAt < rhs.createdAt
        }
      }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }

  /// Precompute reordering even when there are no database writes and the app is closed.
  /// The boundary itself is inclusive; move groups on the first second after it.
  public static func transitionDates(_ games: [WidgetGame], after now: Date) -> [Date] {
    Array(Set(games.compactMap { game -> Date? in
      if game.isPlanned, let date = game.scheduledAt {
        return date.addingTimeInterval(overdueAllowance + 1)
      }
      return game.endedAt?.addingTimeInterval(recentHistory + 1)
    }.filter { $0 > now })).sorted()
  }
}

public nonisolated enum GamesWidgetStore {
  public static let kind = "SupershotGames"

  public static var scheme: String {
    Bundle.main.object(forInfoDictionaryKey: "AppURLScheme") as? String ?? "supershot"
  }

  public static func gameURL(_ id: UUID) -> URL {
    URL(string: "\(scheme)://game/\(id.uuidString)")!
  }

  public static var newGameURL: URL {
    URL(string: "\(scheme)://new-game")!
  }

  public static func fileURL() throws -> URL {
    let group = Bundle.main.object(forInfoDictionaryKey: "GamesWidgetAppGroup") as? String
    guard let group, let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: group
    ) else { throw CocoaError(.fileNoSuchFile) }
    return container.appendingPathComponent("games-widget-v1.json")
  }

  public static func read(from url: URL? = nil) throws -> [WidgetGame] {
    try JSONDecoder().decode([WidgetGame].self, from: Data(contentsOf: url ?? fileURL()))
  }

  public static func write(_ games: [WidgetGame], to url: URL? = nil) throws {
    let url = try url ?? fileURL()
    try JSONEncoder().encode(games).write(to: url, options: .atomic)
  }
}
