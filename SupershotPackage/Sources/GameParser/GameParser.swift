import Dependencies
import Foundation
import OSLog

/// FoundationModels stays behind this boundary; tests can stub generation without bypassing validation.
package nonisolated struct GameParser: Sendable {
  package static let maximumInputBytes = 6000
  package static let maximumFixtures = 12
  package var availability: @Sendable () -> GameParserAvailability
  private var extractStructured: @Sendable (String) -> [ExtractedFixture]?
  private var generate: @Sendable (String) async throws -> [ExtractedFixture]

  package init(
    availability: @escaping @Sendable () -> GameParserAvailability,
    generate: @escaping @Sendable (String) async throws -> [ExtractedFixture],
    extractStructured: @escaping @Sendable (String) -> [ExtractedFixture]? = { _ in nil }
  ) {
    self.availability = availability
    self.generate = generate
    self.extractStructured = extractStructured
  }

  package func parse(_ text: String, context: FixtureParsingContext? = nil) async throws
    -> [FixtureDraft]
  {
    try await GameParserDiagnostics.$requestID.withValue(UUID().uuidString) {
      let logger = GameParserDiagnostics.logger
      let requestID = GameParserDiagnostics.requestID
      let start = ContinuousClock.now
      var stage = "input"
      logger.info("[\(requestID, privacy: .public)] Parse started: bytes=\(text.utf8.count) lines=\(text.unicodeScalars.filter { $0 == "\n" }.count + 1)")
      defer {
        let elapsed = String(describing: start.duration(to: .now))
        logger.info("[\(requestID, privacy: .public)] Parse finished: stage=\(stage, privacy: .public) elapsed=\(elapsed, privacy: .public)")
      }
      do {
        try Task.checkCancellation()
        guard text.utf8.count <= Self.maximumInputBytes else {
          throw GameParserError.inputTooLong(maximumBytes: Self.maximumInputBytes)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw GameParserError.unsupportedInput
        }
        let rows: [ExtractedFixture]
        if let structured = extractStructured(text) {
          stage = "structured"
          rows = structured
          logger.info("[\(requestID, privacy: .public)] Structured extraction: fixtures=\(rows.count)")
        } else {
          stage = "model_availability"
          let status = availability()
          logger.info("[\(requestID, privacy: .public)] Model fallback: availability=\(String(describing: status), privacy: .public)")
          guard status == .available else { throw GameParserError.unavailable(status) }
          stage = "model_generation"
          rows = try await generate(text)
          logger.info("[\(requestID, privacy: .public)] Model extraction: fixtures=\(rows.count)")
        }
        try Task.checkCancellation()
        guard rows.count <= Self.maximumFixtures else {
          throw GameParserError.outputTooLong(maximumFixtures: Self.maximumFixtures)
        }
        guard !rows.isEmpty else { throw GameParserError.unsupportedInput }
        // Require exact, non-overlapping source excerpts, and restore source order independently of generation.
        stage = "source_grounding"
        var located: [(Range<String.Index>, ExtractedFixture)] = []
        for row in rows {
          guard !row.source.isEmpty else {
            logger.error("[\(requestID, privacy: .public)] Source grounding failed: empty excerpt row=\(located.count + 1)")
            throw GameParserError.generationFailed
          }
          var search = text.startIndex ..< text.endIndex
          var match: Range<String.Index>?
          while let range = text.range(of: row.source, range: search) {
            if !located.contains(where: { $0.0.overlaps(range) }) {
              match = range
              break
            }
            search = range.upperBound ..< text.endIndex
          }
          guard let range = match else {
            logger.error("[\(requestID, privacy: .public)] Source grounding failed: missing or overlapping excerpt row=\(located.count + 1)")
            throw GameParserError.generationFailed
          }
          located.append((range, row))
        }
        stage = "validation"
        let drafts = located.sorted { $0.0.lowerBound < $1.0.lowerBound }.map { range, row in
          row.validated(
            dateSource: text,
            sourceLine: text[..<range.lowerBound].unicodeScalars.filter { $0 == "\n" }.count + 1,
            context: context
          )
        }
        for draft in drafts where !draft.issues.isEmpty {
          logger.notice("[\(requestID, privacy: .public)] Validation issues: line=\(draft.sourceLine) issues=\(String(describing: draft.issues), privacy: .public)")
        }
        stage = "success"
        logger.info("[\(requestID, privacy: .public)] Parse succeeded: fixtures=\(drafts.count)")
        return drafts
      } catch is CancellationError {
        logger.info("[\(requestID, privacy: .public)] Parse cancelled")
        throw GameParserError.cancelled
      } catch let error as GameParserError {
        logger.error("[\(requestID, privacy: .public)] Parse failed: stage=\(stage, privacy: .public) error=\(String(describing: error), privacy: .public)")
        if Task.isCancelled {
          throw GameParserError.cancelled
        }
        throw error
      } catch {
        logger.error("[\(requestID, privacy: .public)] Unexpected failure: stage=\(stage, privacy: .public) type=\(String(reflecting: type(of: error)), privacy: .public) detail=\(String(describing: error), privacy: .private)")
        if Task.isCancelled {
          throw GameParserError.cancelled
        }
        throw GameParserError.generationFailed
      }
    }
  }
}

/// Raw, untrusted output. Strings must be verbatim excerpts, including punctuation and metadata labels.
package nonisolated struct ExtractedFixture: Sendable {
  package var source: String
  package var firstTeam: String?
  package var secondTeam: String?
  package var date: String?
  package var time: String?
  package var division: String?
  package var court: String?

  package init(
    source: String,
    firstTeam: String? = nil,
    secondTeam: String? = nil,
    date: String? = nil,
    time: String? = nil,
    division: String? = nil,
    court: String? = nil
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

package extension DependencyValues {
  nonisolated var gameParser: GameParser {
    get { self[GameParserKey.self] }
    set { self[GameParserKey.self] = newValue }
  }
}

private nonisolated enum GameParserKey: DependencyKey {
  static var liveValue: GameParser {
    .live
  }

  static var testValue: GameParser {
    GameParser(availability: { .unavailable }, generate: { _ in [] })
  }
}
