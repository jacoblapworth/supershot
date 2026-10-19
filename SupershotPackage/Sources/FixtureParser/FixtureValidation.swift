import Foundation

nonisolated extension ExtractedFixture {
  func validated(sourceLine: Int, context: FixtureParsingContext?) -> FixtureDraft {
    var issues: [FixtureValidationIssue] = []
    func grounded(_ value: String?, field: String) -> String? {
      guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
      guard source.contains(value) else {
        issues.append(.valueNotInSource(field: field))
        return nil
      }
      return value
    }
    let first = grounded(firstTeam, field: "firstTeam")
    let second = grounded(secondTeam, field: "secondTeam")
    if first == nil { issues.append(.missingFirstTeam) }
    if second == nil { issues.append(.missingSecondTeam) }
    if let first, let second,
      first.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(
        second.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
      issues.append(.identicalTeams)
    }
    let rawDate = grounded(date, field: "date")
    let rawTime = grounded(time, field: "time")
    let division = grounded(division, field: "division")
    let court = grounded(court, field: "court")
    var parsedTime: DateComponents?
    if let rawTime {
      let parts = rawTime.split(separator: ":", omittingEmptySubsequences: false)
      if parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
        (0...23).contains(hour), (0...59).contains(minute),
        parts[0].count <= 2, parts[1].count == 2,
        rawTime.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ":") }) {
        parsedTime = DateComponents(hour: hour, minute: minute)
      } else { issues.append(.invalidTime) }
    }
    var parsedDate: DateComponents?
    if let rawDate {
      let relative = rawDate.lowercased()
      if ["today", "tomorrow", "yesterday"].contains(relative) {
        if let context {
          var calendar = context.calendar
          calendar.timeZone = context.timeZone
          let delta = relative == "tomorrow" ? 1 : relative == "yesterday" ? -1 : 0
          if let date = calendar.date(byAdding: .day, value: delta, to: context.referenceDate) {
            parsedDate = calendar.dateComponents([.year, .month, .day], from: date)
          } else { issues.append(.invalidDate) }
        } else { issues.append(.dateContextRequired) }
      } else {
        // Unambiguous ISO dates only; retain other date text for later correction.
        let parts = rawDate.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
          let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
          year > 0, (1...12).contains(month), (1...31).contains(day),
          rawDate.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "-") }) {
          let components = DateComponents(year: year, month: month, day: day)
          var calendar = Calendar(identifier: .gregorian)
          calendar.timeZone = TimeZone(secondsFromGMT: 0)!
          if let date = calendar.date(from: components),
            calendar.dateComponents([.year, .month, .day], from: date) == components {
            parsedDate = components
          } else { issues.append(.invalidDate) }
        } else { issues.append(.invalidDate) }
      }
    }
    return FixtureDraft(source: source, sourceLine: sourceLine, firstTeam: first, secondTeam: second,
      date: parsedDate, time: parsedTime, dateText: rawDate, timeText: rawTime,
      division: division, court: court, issues: issues)
  }
}
