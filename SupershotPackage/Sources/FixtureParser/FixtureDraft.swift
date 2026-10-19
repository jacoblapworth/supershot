import Foundation

/// Transient extraction data. No database identity, settings, inferred zone or lifecycle state.
nonisolated package struct FixtureDraft: Equatable, Sendable {
  package var source: String
  package var sourceLine: Int
  package var firstTeam: String?
  package var secondTeam: String?
  package var date: DateComponents?
  package var time: DateComponents?
  package var dateText: String?
  package var timeText: String?
  package var division: String?
  package var court: String?
  package var issues: [FixtureValidationIssue]
}

nonisolated package enum FixtureValidationIssue: Equatable, Sendable {
  case missingFirstTeam
  case missingSecondTeam
  case identicalTeams
  case valueNotInSource(field: String)
  case invalidDate
  case invalidTime
  case dateContextRequired
}

/// Context is explicit: time-only input never acquires a date or time zone.
nonisolated package struct FixtureParsingContext: Sendable {
  package var calendar: Calendar
  package var referenceDate: Date
  package var timeZone: TimeZone

  package init(calendar: Calendar, referenceDate: Date, timeZone: TimeZone) {
    self.calendar = calendar
    self.referenceDate = referenceDate
    self.timeZone = timeZone
  }
}

nonisolated package enum FixtureParserAvailability: Equatable, Sendable {
  case available
  case deviceNotEligible
  case intelligenceNotEnabled
  case modelNotReady
  case unavailable
}

nonisolated package enum FixtureParserError: Error, Equatable, Sendable, LocalizedError {
  case unavailable(FixtureParserAvailability)
  case unsupportedInput
  case inputTooLong(maximumBytes: Int)
  case outputTooLong(maximumFixtures: Int)
  case generationFailed
  case cancelled

  package var errorDescription: String? {
    switch self {
    case .unavailable(.deviceNotEligible): "Use a device that supports Apple Intelligence."
    case .unavailable(.intelligenceNotEnabled):
      "Enable Apple Intelligence in Settings, then try again."
    case .unavailable(.modelNotReady):
      "Wait for the on-device model to finish downloading, then try again."
    case .unavailable:
      "The on-device model is unavailable. Try again later or enter fixtures manually."
    case .unsupportedInput: "Paste a matchup or fixture list containing team names."
    case .inputTooLong(let maximum): "Paste a shorter list (at most \(maximum) UTF-8 bytes)."
    case .outputTooLong(let maximum): "Split the list into batches of at most \(maximum) fixtures."
    case .generationFailed: "The fixture list could not be extracted. Try a shorter, simpler list."
    case .cancelled: "Fixture extraction was cancelled."
    }
  }
}
