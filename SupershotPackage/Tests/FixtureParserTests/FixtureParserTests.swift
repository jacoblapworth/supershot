import CustomDump
import Dependencies
import DependenciesTestSupport
@testable import FixtureParser
import Foundation
import Testing

@Suite struct FixtureParserTests {
  func parser(_ rows: [ExtractedFixture]) -> FixtureParser {
    FixtureParser(availability: { .available }, generate: { _ in rows })
  }

  @Test func samplePreservesOrderPunctuationAndMissingDates() async throws {
    let pairs = [
      ("Coles Hot Chooks", "IMG & Friends"), ("Mixed Bag", "Buzz Ballers"),
      ("Buzz Ballers", "Clapham Ballers"), ("Pole vaulters", "Silence of the Lambeths"),
      ("The lodgers", "Netball & Chill"), ("Netball & Chill", "One Team, One Dream"),
    ]
    let times = ["18:30", "19:10", "19:50", "18:30", "19:10", "19:50"]
    let sources = FixtureParserDevelopmentHarness.sample.components(separatedBy: "\n\n")
    let rows = sources.enumerated().map { index, source in
      ExtractedFixture(source: source, firstTeam: pairs[index].0, secondTeam: pairs[index].1,
        time: times[index], division: "Division \(index < 3 ? 1 : 2)", court: "Court \(index < 3 ? 1 : 2)")
    }
    // Validation owns source ordering even if the generator reverses its output.
    let drafts = try await parser(rows.reversed()).parse(FixtureParserDevelopmentHarness.sample)
    expectNoDifference(drafts.count, 6)
    for (index, draft) in drafts.enumerated() {
      expectNoDifference(draft.firstTeam, pairs[index].0)
      expectNoDifference(draft.secondTeam, pairs[index].1)
      expectNoDifference(draft.source, sources[index])
      expectNoDifference(draft.sourceLine, index * 3 + 1)
      expectNoDifference(draft.time, DateComponents(hour: index % 3 == 0 ? 18 : 19,
        minute: [30, 10, 50][index % 3]))
      expectNoDifference(draft.division, "Division \(index < 3 ? 1 : 2)")
      expectNoDifference(draft.court, "Court \(index < 3 ? 1 : 2)")
      #expect(draft.date == nil)
      expectNoDifference(draft.issues, [])
    }
  }

  @Test func singleAndPartialRows() async throws {
    let source = FixtureParserDevelopmentHarness.single
    let drafts = try await parser([.init(source: source, firstTeam: "Coles Hot Chooks", secondTeam: "IMG & Friends")]).parse(source)
    expectNoDifference(drafts.first?.issues, [])
    #expect(drafts.first?.time == nil)
    let partial = try await parser([.init(source: "A vs", firstTeam: "A")]).parse("A vs")
    expectNoDifference(partial.first?.sourceLine, 1)
    expectNoDifference(partial.first?.issues, [.missingSecondTeam])
  }

  @Test func validatesNamesAndRejectsInventedMetadata() async throws {
    let rows = [ExtractedFixture(source: "Chooks vs chooks", firstTeam: "Chooks", secondTeam: "chooks",
      date: "2026-10-19", time: "18:30", division: "Division 1", court: "Court 1")]
    let draft = try #require(try await parser(rows).parse(rows[0].source).first)
    expectNoDifference(draft.issues, [.identicalTeams, .valueNotInSource(field: "date"),
      .valueNotInSource(field: "time"), .valueNotInSource(field: "division"), .valueNotInSource(field: "court")])
    #expect(draft.date == nil && draft.time == nil && draft.division == nil && draft.court == nil)
    let missing = try await parser([.init(source: "vs", firstTeam: " ", secondTeam: "Invented")]).parse("vs")
    expectNoDifference(missing.first?.issues, [.valueNotInSource(field: "secondTeam"), .missingFirstTeam, .missingSecondTeam])
  }

  @Test(arguments: ["24:00", "19:60", "-1:30", "7:5", "noon"])
  func malformedTimesRemainCorrectable(time: String) async throws {
    let source = "\(time) A vs B"
    let draft = try #require(try await parser([.init(source: source, firstTeam: "A", secondTeam: "B", time: time)]).parse(source).first)
    expectNoDifference(draft.timeText, time)
    expectNoDifference(draft.issues, [.invalidTime])
    #expect(draft.time == nil)
  }

  @Test(arguments: ["2026-02-29", "2026-13-01", "2026-00-10", "2026-04-31", "10/11/26"])
  func malformedDatesRemainCorrectable(date: String) async throws {
    let source = "\(date) 18:30 A vs B"
    let draft = try #require(try await parser([.init(source: source, firstTeam: "A", secondTeam: "B", date: date, time: "18:30")]).parse(source).first)
    expectNoDifference(draft.dateText, date)
    expectNoDifference(draft.issues, [.invalidDate])
    expectNoDifference(draft.time, DateComponents(hour: 18, minute: 30))
    #expect(draft.date == nil)
  }

  @Test func explicitAndRelativeDatesUseSuppliedContext() async throws {
    var calendar = Calendar(identifier: .gregorian)
    let zone = try #require(TimeZone(identifier: "Pacific/Auckland"))
    calendar.timeZone = zone
    // UTC date is still 18 October; local date is 19 October.
    let reference = try #require(ISO8601DateFormatter().date(from: "2026-10-18T12:30:00Z"))
    let context = FixtureParsingContext(calendar: calendar, referenceDate: reference, timeZone: zone)
    for (date, expected) in [("2028-02-29", DateComponents(year: 2028, month: 2, day: 29)),
      ("tomorrow", DateComponents(year: 2026, month: 10, day: 20)),
      ("today", DateComponents(year: 2026, month: 10, day: 19)),
      ("yesterday", DateComponents(year: 2026, month: 10, day: 18))] {
      let source = "\(date) A vs B"
      let result = try await parser([.init(source: source, firstTeam: "A", secondTeam: "B", date: date)]).parse(source, context: context)
      expectNoDifference(result.first?.date, expected)
      expectNoDifference(result.first?.issues, [])
      #expect(result.first?.date?.timeZone == nil)
    }
    let source = "tomorrow A vs B"
    let result = try await parser([.init(source: source, firstTeam: "A", secondTeam: "B", date: "tomorrow")]).parse(source)
    expectNoDifference(result.first?.issues, [.dateContextRequired])
    #expect(result.first?.date == nil)
  }

  @Test func emptyIrrelevantUnavailableAndLimits() async throws {
    let neverGenerate = FixtureParser(availability: { .available }, generate: { _ in
      Issue.record("Generation should not run")
      return []
    })
    await #expect(throws: FixtureParserError.unsupportedInput) { try await neverGenerate.parse(" \n") }
    await #expect(throws: FixtureParserError.inputTooLong(maximumBytes: 6_000)) {
      try await neverGenerate.parse(String(repeating: "&", count: 6_001))
    }
    await #expect(throws: FixtureParserError.unsupportedInput) { try await parser([]).parse("Shopping list") }
    for status in [FixtureParserAvailability.deviceNotEligible, .intelligenceNotEnabled, .modelNotReady, .unavailable] {
      let unavailable = FixtureParser(availability: { status }, generate: neverGenerateGeneration)
      await #expect(throws: FixtureParserError.unavailable(status)) { try await unavailable.parse("A vs B") }
    }
    await #expect(throws: FixtureParserError.outputTooLong(maximumFixtures: 12)) {
      try await parser(Array(repeating: .init(source: "A vs B"), count: 13)).parse("A vs B")
    }
  }

  @Test func rejectsFabricatedSourceAndMapsFailures() async throws {
    await #expect(throws: FixtureParserError.generationFailed) {
      try await parser([.init(source: "invented")]).parse("A vs B")
    }
    let failure = FixtureParser(availability: { .available }, generate: { _ in throw CocoaError(.coderInvalidValue) })
    await #expect(throws: FixtureParserError.generationFailed) { try await failure.parse("A vs B") }
    let cancelled = FixtureParser(availability: { .available }, generate: { _ in throw CancellationError() })
    await #expect(throws: FixtureParserError.cancelled) { try await cancelled.parse("A vs B") }
  }

  @Test func cancellationAfterGenerationDiscardsDrafts() async {
    let task = Task {
      let parser = FixtureParser(availability: { .available }, generate: { _ in
        withUnsafeCurrentTask { $0?.cancel() }
        return [.init(source: "A vs B", firstTeam: "A", secondTeam: "B")]
      })
      await #expect(throws: FixtureParserError.cancelled) { try await parser.parse("A vs B") }
    }
    await task.value
  }

  @Test func dependencyCanBeOverridden() async throws {
    let stub = parser([.init(source: "A vs B", firstTeam: "A", secondTeam: "B")])
    let drafts = try await withDependencies {
      $0.fixtureParser = stub
    } operation: {
      @Dependency(\.fixtureParser) var parser
      return try await parser.parse("A vs B")
    }
    expectNoDifference(drafts.first?.firstTeam, "A")
  }
}

nonisolated private func neverGenerateGeneration(_: String) async throws -> [ExtractedFixture] {
  Issue.record("Unavailable parser must not generate")
  return []
}
