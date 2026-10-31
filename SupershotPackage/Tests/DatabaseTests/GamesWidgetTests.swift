import Foundation
import Testing
import WidgetSupport

struct GamesWidgetTests {
  private let now = Date(timeIntervalSince1970: 1_000_000)

  private func game(_ number: Int, scheduled: TimeInterval? = nil,
                    started: TimeInterval? = nil, ended: TimeInterval? = nil) -> WidgetGame
  {
    WidgetGame(
      id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!,
      createdAt: now, scheduledAt: scheduled.map { now.addingTimeInterval($0) },
      startedAt: started.map { now.addingTimeInterval($0) },
      endedAt: ended.map { now.addingTimeInterval($0) },
      teamAName: "Thunder", teamAColorHex: "#007AFF", teamAScore: 123,
      teamBName: "Lightning", teamBColorHex: "#FF3B30", teamBScore: 98
    )
  }

  @Test func priorityAndDeterministicTies() {
    let games = [
      game(8), game(7, scheduled: -90000), game(6, started: -1000, ended: -100),
      game(5, started: -1000, ended: -10), game(4, started: -100),
      game(3, scheduled: 60), game(2, scheduled: -86400), game(1, scheduled: -86400),
      game(9, started: -900_000, ended: -GamesWidgetSelection.recentHistory - 1),
    ]
    let expected = [1, 2, 3, 4, 5, 6, 7, 8].map { game($0).id }
    #expect(GamesWidgetSelection.games(games, at: now).map(\.id) == expected)
    #expect(GamesWidgetSelection.games(games.reversed(), at: now).map(\.id) == expected)
  }

  @Test func rollingOverdueBoundaryAndTimelineWithoutEdits() throws {
    let planned = game(1, scheduled: -86400)
    let live = game(2, started: -60)
    let games = [live, planned]
    for offset in [-0.001, 0] {
      #expect(GamesWidgetSelection.games(games, at: now.addingTimeInterval(offset)).first?.id == planned.id)
    }
    #expect(GamesWidgetSelection.games(games, at: now.addingTimeInterval(0.001)).first?.id == live.id)
    let transition = try #require(GamesWidgetSelection.transitionDates(games, after: now).first)
    #expect(transition == now.addingTimeInterval(1))
    #expect(GamesWidgetSelection.games(games, at: transition).first?.id == live.id)
    #expect(planned.isPlanned)
  }

  @Test func completionHistoryExpiresWithoutAnEdit() throws {
    let completed = game(1, started: -900_000, ended: -GamesWidgetSelection.recentHistory)
    #expect(GamesWidgetSelection.games([completed], at: now).count == 1)
    #expect(GamesWidgetSelection.games([completed], at: now.addingTimeInterval(0.001)).isEmpty)
    let transition = try #require(GamesWidgetSelection.transitionDates([completed], after: now).first)
    #expect(GamesWidgetSelection.games([completed], at: transition).isEmpty)
  }

  @Test func snapshotRoundTripAndDeletion() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let games = [game(1, scheduled: 3600), game(2, started: -600, ended: -60)]
    try GamesWidgetStore.write(games, to: url)
    #expect(try GamesWidgetStore.read(from: url) == games)
    #expect(try GamesWidgetStore.read(from: url)[1].teamAScore == 123)
    try GamesWidgetStore.write([], to: url)
    #expect(try GamesWidgetStore.read(from: url).isEmpty)
    try Data("invalid".utf8).write(to: url)
    #expect(throws: (any Error).self) { try GamesWidgetStore.read(from: url) }
  }
}
