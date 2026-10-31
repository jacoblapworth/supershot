import Foundation

nonisolated extension ExtractedFixture {
  func validated(sourceLine: Int, context: FixtureParsingContext?) -> FixtureDraft {
    var issues: [FixtureValidationIssue] = []
    func grounded(_ value: String?, field: String) -> String? {
      guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
      }
      guard source.contains(value) else {
        issues.append(.valueNotInSource(field: field))
        return nil
      }
      return value
    }
    let first = grounded(firstTeam, field: "firstTeam")
    let second = grounded(secondTeam, field: "secondTeam")
    if first == nil {
      issues.append(.missingFirstTeam)
    }
    if second == nil {
      issues.append(.missingSecondTeam)
    }
    if let first, let second,
       first.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(second.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    {
      issues.append(.identicalTeams)
    }
    var rawDate = grounded(date, field: "date")
    let rawTime = grounded(time, field: "time")
    let division = grounded(division, field: "division")
    let court = grounded(court, field: "court")
    var parsedTime: DateComponents?
    if let rawTime {
      parsedTime = parseFixtureTime(rawTime)
      if parsedTime == nil {
        issues.append(.invalidTime)
      }
    }
    // A valid clock time repeated in the date slot is not evidence of a calendar date.
    // The on-device model can populate both slots from a time-only fixture.
    if parsedTime != nil, rawDate == rawTime {
      rawDate = nil
    }
    var parsedDate: DateComponents?
    if let rawDate {
      let relative = rawDate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if ["today", "tomorrow", "yesterday"].contains(relative) {
        if let context {
          var calendar = context.calendar
          calendar.timeZone = context.timeZone
          let delta = relative == "tomorrow" ? 1 : relative == "yesterday" ? -1 : 0
          if let date = calendar.date(byAdding: .day, value: delta, to: context.referenceDate) {
            parsedDate = calendar.dateComponents([.year, .month, .day], from: date)
          } else {
            issues.append(.invalidDate)
          }
        } else {
          issues.append(.dateContextRequired)
        }
      } else if let weekday = fixtureWeekday(relative) {
        if let context {
          var calendar = context.calendar
          calendar.timeZone = context.timeZone
          let start = calendar.startOfDay(for: context.referenceDate)
          let after = relative.hasPrefix("next ") ? start : start.addingTimeInterval(-1)
          if let date = calendar.nextDate(
            after: after,
            matching: DateComponents(weekday: weekday),
            matchingPolicy: .nextTime
          ) {
            parsedDate = calendar.dateComponents([.year, .month, .day], from: date)
          } else {
            issues.append(.invalidDate)
          }
        } else {
          issues.append(.dateContextRequired)
        }
      } else {
        // Unambiguous ISO dates only; retain other date text for later correction.
        let parts = rawDate.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
           let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
           year > 0, (1 ... 12).contains(month), (1 ... 31).contains(day),
           rawDate.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "-") })
        {
          let components = DateComponents(year: year, month: month, day: day)
          var calendar = Calendar(identifier: .gregorian)
          calendar.timeZone = TimeZone(secondsFromGMT: 0)!
          if let date = calendar.date(from: components),
             calendar.dateComponents([.year, .month, .day], from: date) == components
          {
            parsedDate = components
          } else {
            issues.append(.invalidDate)
          }
        } else {
          issues.append(.invalidDate)
        }
      }
    }
    return FixtureDraft(
      source: source,
      sourceLine: sourceLine,
      firstTeam: first,
      secondTeam: second,
      date: parsedDate,
      time: parsedTime,
      dateText: rawDate,
      timeText: rawTime,
      division: division,
      court: court,
      issues: issues
    )
  }
}

private nonisolated func parseFixtureTime(_ text: String) -> DateComponents? {
  var value = text.lowercased().filter { !$0.isWhitespace && $0 != "." }
  let isAM = value.hasSuffix("am")
  let isPM = value.hasSuffix("pm")
  if isAM || isPM {
    value.removeLast(2)
  }
  let parts = value.split(separator: ":", omittingEmptySubsequences: false)
  guard (1 ... 2).contains(parts.count),
        value.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ":") }),
        (1 ... 2).contains(parts[0].count), let hour = Int(parts[0])
  else { return nil }
  let minute: Int
  if parts.count == 2 {
    guard parts[1].count == 2, let parsed = Int(parts[1]), (0 ... 59).contains(parsed)
    else { return nil }
    minute = parsed
  } else {
    guard isAM || isPM else { return nil }
    minute = 0
  }
  if isAM || isPM {
    guard (1 ... 12).contains(hour) else { return nil }
    return DateComponents(hour: hour % 12 + (isPM ? 12 : 0), minute: minute)
  }
  guard (0 ... 23).contains(hour) else { return nil }
  return DateComponents(hour: hour, minute: minute)
}

private nonisolated func fixtureWeekday(_ text: String) -> Int? {
  let value = text.hasPrefix("next ") ? String(text.dropFirst(5)) : text
  let days = [
    ["sunday", "sun"],
    ["monday", "mon"],
    ["tuesday", "tue"],
    ["wednesday", "wed"],
    ["thursday", "thu"],
    ["friday", "fri"],
    ["saturday", "sat"],
  ]
  return days.firstIndex { $0.contains(value) }.map { $0 + 1 }
}
