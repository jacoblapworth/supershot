import Foundation
@testable import GameParser
import Testing

struct BulkFixtureParsingTests {
  static let sample = """
  League name : Netball - Mixed (Clapham (Lambeth Academy) - Tues - Rec)

  Tue 03/11/2026

  19:50  Coles Hot Chooks vs The lodgers
  Division 1 • Court 1
  19:10  Clapham Ballers vs Pole vaulters
  Division 1 • Court 1
  18:30  Buzz Ballers vs IMG & Friends
  Division 1 • Court 1
  18:30  One Team, One Dream vs Silence of the Lambeths
  Division 2 • Court 2
  19:10  Silence of the Lambeths vs Netball & Chill
  Division 2 • Court 2
  19:50  Benny and the Nets vs Mixed Bag
  Division 2 • Court 2
  """

  static let balham = """
  League name : Netball - Mixed (Balham - Mon - Rec)

  Mon 09/11/2026

  19:00   \t   Division 1   \t   Mangos vs Mixteama Aguilera   \t   Court 2
  19:45   \t   Division 1   \t   Slappers vs Peaches   \t   Court 2
  20:30   \t   Division 1   \t   Get your balls out vs Hoops I did it again!   \t   Court 2
  """

  @Test(arguments: ["mixed", "tabs", "spaces", "nbsp", "crlf"])
  func suppliedBalhamScheduleParsesWithoutModel(whitespace: String) async throws {
    var text = Self.balham
    switch whitespace {
    case "tabs": text = text.replacingOccurrences(of: "   \t   ", with: "\t")
    case "spaces": text = text.replacingOccurrences(of: "\t", with: "  ")
    case "nbsp": text = text.replacingOccurrences(of: "   \t   ", with: "\u{00a0}\u{00a0}")
    case "crlf": text = text.replacingOccurrences(of: "\n", with: "\r\n")
    default: break
    }
    let parser = GameParser(availability: { .deviceNotEligible }, generate: { _ in
      Issue.record("Tabular schedules must not use the model")
      return []
    }, extractStructured: StructuredFixtureExtractor.extract)
    let fixtures = try await parser.parse(text)
    #expect(fixtures.map(\.firstTeam) == ["Mangos", "Slappers", "Get your balls out"])
    #expect(fixtures.map(\.secondTeam) == ["Mixteama Aguilera", "Peaches", "Hoops I did it again!"])
    #expect(fixtures.map(\.time) == [DateComponents(hour: 19, minute: 0), DateComponents(hour: 19, minute: 45), DateComponents(hour: 20, minute: 30)])
    #expect(fixtures.map(\.sourceLine) == [5, 6, 7])
    #expect(fixtures.allSatisfy {
      $0.date == DateComponents(year: 2026, month: 11, day: 9)
        && $0.division == "Division 1" && $0.court == "Court 2" && $0.issues.isEmpty
        && text.contains($0.source)
    })
  }

  @Test(arguments: [
    "19:00  Division 1  A vs B  Court 2\nC against D later",
    "19:00  Division 1  A vs B  Court 2 extra unknown content",
    "19:00  Division 1  A vs B  Court 2\nDivision 2 • Court 3",
    "19:00  Division 1  A vs B vs C  Court 2",
  ])
  func ambiguousTablesFallBackWithoutDroppingContent(text: String) {
    #expect(StructuredFixtureExtractor.extract(text) == nil)
  }

  @Test func tableDatesCanChangeAndLimitsStillApply() async throws {
    let parser = GameParser(availability: { .unavailable }, generate: { _ in [] }, extractStructured: StructuredFixtureExtractor.extract)
    let row = "19:00  Division 1  A vs B  Court 2"
    let drafts = try await parser.parse("Mon 09/11/2026\n\(row)\nTue 10/11/2026\n\(row)")
    #expect(drafts.map(\.date) == [DateComponents(year: 2026, month: 11, day: 9), DateComponents(year: 2026, month: 11, day: 10)])
    await #expect(throws: GameParserError.outputTooLong(maximumFixtures: 12)) {
      try await parser.parse(Array(repeating: row, count: 13).joined(separator: "\n"))
    }
  }

  @Test func suppliedScheduleParsesWithoutModel() async throws {
    let parser = GameParser(availability: { .deviceNotEligible }, generate: { _ in
      Issue.record("Structured schedule must not use the model")
      return []
    }, extractStructured: StructuredFixtureExtractor.extract)
    let fixtures = try await parser.parse(Self.sample)
    #expect(fixtures.count == 6)
    #expect(fixtures.map(\.firstTeam) == ["Coles Hot Chooks", "Clapham Ballers", "Buzz Ballers", "One Team, One Dream", "Silence of the Lambeths", "Benny and the Nets"])
    #expect(fixtures.map(\.timeText) == ["19:50", "19:10", "18:30", "18:30", "19:10", "19:50"])
    #expect(fixtures.map(\.court) == ["Court 1", "Court 1", "Court 1", "Court 2", "Court 2", "Court 2"])
    #expect(fixtures.map(\.division) == ["Division 1", "Division 1", "Division 1", "Division 2", "Division 2", "Division 2"])
    #expect(fixtures.allSatisfy { $0.date == DateComponents(year: 2026, month: 11, day: 3) && $0.issues.isEmpty })
  }

  @Test func repeatedRowsKeepTheirOwnMetadataAndSource() async throws {
    let text = "18:30 A vs B\nDivision 1 • Court 1\n\n18:30 A vs B\nDivision 2 • Court 2"
    let parser = GameParser(availability: { .unavailable }, generate: { _ in [] }, extractStructured: StructuredFixtureExtractor.extract)
    let fixtures = try await parser.parse(text)
    #expect(fixtures.map(\.sourceLine) == [1, 4])
    #expect(fixtures.map(\.court) == ["Court 1", "Court 2"])
  }

  @Test func unknownTrailingContentDoesNotSilentlyDropFixtures() {
    #expect(StructuredFixtureExtractor.extract("18:30 A vs B\nC against D later") == nil)
    #expect(StructuredFixtureExtractor.extract("18:30 A vs B\nTue 03/11/2026") == nil)
  }

  @Test func invalidBritishDateRequiresCorrection() async throws {
    let parser = GameParser(availability: { .unavailable }, generate: { _ in [] }, extractStructured: StructuredFixtureExtractor.extract)
    let fixtures = try await parser.parse("Tue 31/02/2026\n18:30 A vs B")
    #expect(fixtures[0].date == nil)
    #expect(fixtures[0].issues.contains(.invalidDate))
  }
}
