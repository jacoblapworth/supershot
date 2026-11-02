import Database
import Dependencies
import Foundation
@testable import GamesFeature
import Testing
import TestSupport

struct CompletedGameSectionTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    return calendar
  }

  @Test
  func groupsByPlayedDayWithNewestSectionsAndGamesFirst() {
    let morning = date(2026, 11, 1, 9)
    let evening = date(2026, 11, 1, 18)
    let previous = date(2026, 10, 31, 23)
    let sections = CompletedGameSection.sections(from: [
      game(1, startedAt: morning, endedAt: evening),
      game(2, startedAt: previous, endedAt: morning),
      game(3, startedAt: evening, endedAt: evening),
      game(4, startedAt: morning, endedAt: nil),
      game(5, startedAt: nil, endedAt: nil),
    ], calendar: calendar)
    #expect(sections.map(\.day) == [date(2026, 11, 1, 0), date(2026, 10, 31, 0)])
    #expect(sections.map { $0.games.map(\.id) } == [[UUID(3), UUID(1)], [UUID(2)]])
  }

  @Test
  func usesLocalCalendarDayAcrossDaylightSavingBoundary() {
    let first = date(2026, 10, 25, 0)
    let last = date(2026, 10, 25, 23)
    let sections = CompletedGameSection.sections(from: [
      game(1, startedAt: first, endedAt: first),
      game(2, startedAt: last, endedAt: last),
    ], calendar: calendar)
    #expect(sections.count == 1)
    #expect(sections.first?.day == first)
    #expect(sections.first?.games.map(\.id) == [UUID(2), UUID(1)])
  }

  @Test
  func missingStartUsesCompletionDateAndEqualTimesHaveStableOrder() {
    let day = date(2026, 11, 1, 12)
    let games = [game(1, startedAt: nil, endedAt: day), game(2, startedAt: nil, endedAt: day)]
    let sections = CompletedGameSection.sections(from: games, calendar: calendar)
    #expect(sections.first?.day == calendar.startOfDay(for: day))
    #expect(sections.first?.games.map(\.id) == [UUID(2), UUID(1)])
    #expect(CompletedGameSection.sections(from: [], calendar: calendar).isEmpty)
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
  }

  private func game(_ id: Int, startedAt: Date?, endedAt: Date?) -> GameListItem {
    GameListItem(
      endedAt: endedAt,
      id: UUID(id),
      startedAt: startedAt,
      teamAName: "Foxes",
      teamAScore: 18,
      teamBName: "Owls",
      teamBScore: 24
    )
  }
}
