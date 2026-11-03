import Foundation

/// A conservative fast path for fixture rows with an explicit clock time and versus delimiter.
/// Recognizes explicit league/date headers and division/court lines; unknown lines use the model.
nonisolated enum StructuredFixtureExtractor {
  static func extract(_ text: String) -> [ExtractedFixture]? {
    let rows = text.split(whereSeparator: \.isNewline).map(String.init)
      .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    guard !rows.isEmpty else { return nil }
    let rowPattern = #"^\s*((?:[01]?[0-9]|2[0-3]):[0-5][0-9])\s+(.+?)\s+(?i:vs?\.?)\s+(.+?)\s*$"#
    let separatorPattern = #"(?i)\s+vs?\.?\s+"#
    // Do not consume metadata, a second fixture, or natural-language scheduling as a team name.
    let metadataPattern = #"(?i)\b(court|division|today|tomorrow|yesterday|tonight|next|monday|tuesday|wednesday|thursday|friday|saturday|sunday|at|on)\b|[0-9]{1,2}:[0-9]{2}|[0-9]+[-/][0-9]+"#
    guard let rowRegex = try? NSRegularExpression(pattern: rowPattern),
          let separatorRegex = try? NSRegularExpression(pattern: separatorPattern),
          let metadataRegex = try? NSRegularExpression(pattern: metadataPattern)
    else { return nil }
    var fixtures: [ExtractedFixture] = []
    var sharedDate: String?
    var pendingHeader = false
    var cursor = text.startIndex
    var fixtureStart: String.Index?
    for row in rows {
      guard let rowRange = text.range(of: row, range: cursor ..< text.endIndex) else { return nil }
      cursor = rowRange.upperBound
      let trimmed = row.trimmingCharacters(in: .whitespaces)
      if trimmed.range(of: #"(?i)^league name\s*:"#, options: .regularExpression) != nil {
        guard fixtures.isEmpty else { return nil }
        pendingHeader = true
        continue
      }
      if trimmed.range(of: #"^(?:(?i:mon|tue|wed|thu|fri|sat|sun)\s+)?(?:[0-9]{2}/[0-9]{2}/[0-9]{4}|[0-9]{4}-[0-9]{2}-[0-9]{2})$"#, options: .regularExpression) != nil {
        sharedDate = trimmed.split(whereSeparator: \.isWhitespace).last.map(String.init)
        pendingHeader = true
        continue
      }
      if trimmed.range(of: #"(?i)^division\s+.+?\s*[•·]\s*court\s+.+$"#, options: .regularExpression) != nil {
        guard !fixtures.isEmpty, !pendingHeader else { return nil }
        let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: "•·"))
        // Keep the actual contiguous source, including blank lines.
        guard let fixtureStart, fixtures[fixtures.count - 1].division == nil else { return nil }
        fixtures[fixtures.count - 1].source = String(text[fixtureStart ..< rowRange.upperBound])
        fixtures[fixtures.count - 1].division = parts[0].trimmingCharacters(in: .whitespaces)
        fixtures[fixtures.count - 1].court = parts[1].trimmingCharacters(in: .whitespaces)
        continue
      }
      let range = NSRange(row.startIndex..., in: row)
      guard separatorRegex.numberOfMatches(in: row, range: range) == 1,
            let match = rowRegex.firstMatch(in: row, range: range),
            let timeRange = Range(match.range(at: 1), in: row),
            let firstRange = Range(match.range(at: 2), in: row),
            let secondRange = Range(match.range(at: 3), in: row)
      else { return nil }
      let first = String(row[firstRange])
      let second = String(row[secondRange])
      guard !first.trimmingCharacters(in: .whitespaces).isEmpty,
            !second.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
      for name in [first, second] {
        guard metadataRegex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) == nil
        else { return nil }
      }
      fixtures.append(ExtractedFixture(source: row, firstTeam: first, secondTeam: second, date: sharedDate, time: String(row[timeRange])))
      pendingHeader = false
      fixtureStart = rowRange.lowerBound
    }
    guard !pendingHeader else { return nil }
    return fixtures
  }
}
