import Foundation
import GameParser

/// Uses the same explicit date/time-zone context as extraction, then exposes
/// the interpreted schedule in the normal setup controls for review.
package nonisolated struct DescribedGameMetadata: Equatable, Sendable {
  package var scheduledAt: Date?
  package var court: String?
  package var division: String?
  package var notices: [String] = []

  package init(scheduledAt: Date? = nil, court: String? = nil, division: String? = nil) {
    self.scheduledAt = scheduledAt
    self.court = court
    self.division = division
  }

  package init(fixture: FixtureDraft, context: FixtureParsingContext) {
    self.init(
      court: Self.value(fixture.court, removing: "court"),
      division: Self.value(fixture.division, removing: "division")
    )
    guard fixture.dateText != nil || fixture.timeText != nil else { return }
    if fixture.dateText != nil && fixture.date == nil
      || fixture.timeText != nil && fixture.time == nil
    {
      notices.append("Check the schedule: the date or time could not be read. Set it below.")
      return
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = context.timeZone
    let today = calendar.dateComponents([.year, .month, .day], from: context.referenceDate)
    let currentTime = calendar.dateComponents([.hour, .minute], from: context.referenceDate)
    var components = fixture.date ?? today
    components.hour = fixture.time?.hour ?? currentTime.hour
    components.minute = fixture.time?.minute ?? currentTime.minute
    components.second = 0
    if let date = calendar.date(from: components),
       calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date) == components
    {
      scheduledAt = date
      if fixture.date == nil {
        notices.append("Using today for the time in your description. Check the schedule below.")
      }
      if fixture.time == nil {
        notices.append("No time was provided, so the schedule uses the current time. Check it below.")
      }
    } else {
      notices.append("That local date or time is not valid in your time zone. Set the schedule below.")
    }
  }

  private static func value(_ text: String?, removing label: String) -> String? {
    guard let text else { return nil }
    let value = text.replacingOccurrences(
      of: "(?i)^\\s*\(label)\\b\\s*[:#-]?\\s*",
      with: "", options: .regularExpression
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}
