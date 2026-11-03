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
