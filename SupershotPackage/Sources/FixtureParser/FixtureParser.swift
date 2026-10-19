import Dependencies
import Foundation

/// FoundationModels stays behind this boundary; tests can stub generation without bypassing validation.
nonisolated package struct FixtureParser: Sendable {
  package static let maximumInputBytes = 6_000
  package static let maximumFixtures = 12
  package var availability: @Sendable () -> FixtureParserAvailability
  private var generate: @Sendable (String) async throws -> [ExtractedFixture]

  package init(
    availability: @escaping @Sendable () -> FixtureParserAvailability,
    generate: @escaping @Sendable (String) async throws -> [ExtractedFixture]
  ) {
    self.availability = availability
    self.generate = generate
  }

  package func parse(_ text: String, context: FixtureParsingContext? = nil) async throws
    -> [FixtureDraft]
  {
    do {
      try Task.checkCancellation()
      guard text.utf8.count <= Self.maximumInputBytes else {
        throw FixtureParserError.inputTooLong(maximumBytes: Self.maximumInputBytes)
      }
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw FixtureParserError.unsupportedInput
      }
      let status = availability()
      guard status == .available else { throw FixtureParserError.unavailable(status) }
      let rows = try await generate(text)
      try Task.checkCancellation()
      guard rows.count <= Self.maximumFixtures else {
        throw FixtureParserError.outputTooLong(maximumFixtures: Self.maximumFixtures)
      }
      guard !rows.isEmpty else { throw FixtureParserError.unsupportedInput }
      // Require exact, non-overlapping source excerpts, and restore source order independently of generation.
      var located: [(Range<String.Index>, ExtractedFixture)] = []
      for row in rows {
        guard !row.source.isEmpty else { throw FixtureParserError.generationFailed }
        var search = text.startIndex..<text.endIndex
        var match: Range<String.Index>?
        while let range = text.range(of: row.source, range: search) {
          if !located.contains(where: { $0.0.overlaps(range) }) {
            match = range
            break
          }
          search = range.upperBound..<text.endIndex
        }
        guard let range = match else { throw FixtureParserError.generationFailed }
        located.append((range, row))
      }
      return located.sorted { $0.0.lowerBound < $1.0.lowerBound }.map { range, row in
        row.validated(
          sourceLine: text[..<range.lowerBound].filter { $0 == "\n" }.count + 1,
          context: context
        )
      }
    } catch is CancellationError {
      throw FixtureParserError.cancelled
    } catch let error as FixtureParserError {
      if Task.isCancelled { throw FixtureParserError.cancelled }
      throw error
    } catch {
      if Task.isCancelled { throw FixtureParserError.cancelled }
      throw FixtureParserError.generationFailed
    }
  }
}

/// Raw, untrusted output. Strings must be verbatim excerpts, including punctuation and metadata labels.
nonisolated package struct ExtractedFixture: Sendable {
  package var source: String
  package var firstTeam: String?
  package var secondTeam: String?
  package var date: String?
  package var time: String?
  package var division: String?
  package var court: String?

  package init(
    source: String, firstTeam: String? = nil, secondTeam: String? = nil,
    date: String? = nil, time: String? = nil, division: String? = nil, court: String? = nil
  ) {
    self.source = source
    self.firstTeam = firstTeam
    self.secondTeam = secondTeam
    self.date = date
    self.time = time
    self.division = division
    self.court = court
  }
}

extension DependencyValues {
  nonisolated package var fixtureParser: FixtureParser {
    get { self[FixtureParserKey.self] }
    set { self[FixtureParserKey.self] = newValue }
  }
}

private nonisolated enum FixtureParserKey: DependencyKey {
  static var liveValue: FixtureParser { .live }
  static var testValue: FixtureParser {
    FixtureParser(availability: { .unavailable }, generate: { _ in [] })
  }
}
