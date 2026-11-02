import Database
import Dependencies
import Foundation
import GameCore
import SharedModels
import SQLiteData
import Testing
import TestSupport

extension SupershotTestSuite {
  @MainActor
  struct GameListClockTests {
    private let now = Date(timeIntervalSince1970: 10000)

    @Test
    func queryIncludesPersistedClock() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let game = Game(
        id: UUID(100),
        startedAt: now,
        teamAID: UUID(101),
        teamBID: UUID(102),
        currentPhaseIndex: 1,
        elapsedSeconds: 12,
        timerEndsAt: now.addingTimeInterval(30),
        breakStartPolicy: .manual
      )
      try await database.write { db in
        try db.seed {
          Team(id: UUID(101), name: "Foxes", colorHex: "#FF9A00")
          Team(id: UUID(102), name: "Owls", colorHex: "#FF2729")
          game
        }
        try GamePeriod.insert {
          testGamePeriods(gameID: game.id, durationSeconds: 900, breakDurations: [60, 60, 60])
        }.execute(db)
      }
      let row = try await database.read { db in
        try #require(GamesRequest().fetch(db).games.first { $0.id == game.id })
      }
      #expect(row.timing == game.timing)
      #expect(row.clockDisplay(at: now)?.isBreak == true)
      #expect(row.clockDisplay(at: now)?.remainingSeconds == 30)
    }

    @Test
    func runningAndPausedClocks() {
      var row = makeRow()
      row.timing.countdown = .init(endsAt: now.addingTimeInterval(89))
      #expect(row.clockDisplay(at: now)?.remainingSeconds == 89)
      #expect(row.clockDisplay(at: now.addingTimeInterval(1))?.remainingSeconds == 88)
      row.timing.countdown = .init(elapsedSeconds: 100)
      #expect(row.clockDisplay(at: now)?.remainingSeconds == 800)
      #expect(row.clockDisplay(at: now.addingTimeInterval(100))?.remainingSeconds == 800)
    }

    @Test(arguments: [BreakStartPolicy.automatic, .manual])
    func expiredPeriodUsesBreakPolicy(_ policy: BreakStartPolicy) throws {
      var row = makeRow()
      row.timing.breakStartPolicy = policy
      row.timing.countdown = .init(endsAt: now.addingTimeInterval(-10))
      let stored = row.timing
      let display = try #require(row.clockDisplay(at: now))
      #expect(display.isBreak)
      #expect(display.period == 1)
      #expect(display.remainingSeconds == (policy == .automatic ? 50 : 60))
      #expect(row.timing == stored)
    }

    @Test
    func expiredBreakWaitsForManualPeriodStart() throws {
      var row = makeRow()
      row.timing = .init(phaseIndex: 1, countdown: .init(endsAt: now.addingTimeInterval(-10)))
      let display = try #require(row.clockDisplay(at: now))
      #expect(!display.isBreak)
      #expect(display.period == 2)
      #expect(display.remainingSeconds == 900)
    }

    @Test
    func finalPeriodStopsAtZero() throws {
      var row = makeRow()
      row.timing = .init(phaseIndex: 6, countdown: .init(endsAt: now.addingTimeInterval(-10)))
      let display = try #require(row.clockDisplay(at: now))
      #expect(display.period == 4)
      #expect(display.remainingSeconds == 0)
    }

    @Test
    func missingTimelineHasNoClock() {
      var row = makeRow()
      row.periods = []
      #expect(row.clockDisplay(at: now) == nil)
    }

    private func makeRow() -> GameListItem {
      GameListItem(
        id: UUID(100),
        periods: testGamePeriods(gameID: UUID(100), durationSeconds: 900, breakDurations: [60, 60, 60]),
        startedAt: now,
        teamAName: "Foxes",
        teamAScore: 18,
        teamBName: "Owls",
        teamBScore: 24
      )
    }
  }
}
