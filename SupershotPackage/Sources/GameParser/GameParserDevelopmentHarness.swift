import Foundation

/// Callable on an eligible iOS device or Mac. Deliberately has no persistence or app lifecycle dependencies.
package nonisolated enum GameParserDevelopmentHarness {
  package static let single = "Coles Hot Chooks vs IMG & Friends"
  package static let sample = """
  18:30  Coles Hot Chooks vs IMG & Friends
  Division 1 • Court 1

  19:10  Mixed Bag vs Buzz Ballers
  Division 1 • Court 1

  19:50  Buzz Ballers vs Clapham Ballers
  Division 1 • Court 1

  18:30  Pole vaulters vs Silence of the Lambeths
  Division 2 • Court 2

  19:10  The lodgers vs Netball & Chill
  Division 2 • Court 2

  19:50  Netball & Chill vs One Team, One Dream
  Division 2 • Court 2
  """

  package struct Report: Sendable {
    package var availability: GameParserAvailability
    package var elapsed: Duration
    package var result: Result<[FixtureDraft], GameParserError>
  }

  package static func run(
    text: String = sample,
    context: FixtureParsingContext? = nil,
    parser: GameParser = .live
  ) async -> Report {
    let clock = ContinuousClock()
    let start = clock.now
    let availability = parser.availability()
    let result: Result<[FixtureDraft], GameParserError>
    do { result = try await .success(parser.parse(text, context: context)) } catch let error
      as GameParserError
    { result = .failure(error) } catch { result = .failure(.generationFailed) }
    return Report(
      availability: availability, elapsed: start.duration(to: clock.now), result: result
    )
  }
}
