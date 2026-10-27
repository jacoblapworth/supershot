import Foundation

/// A conservative fast path for fixture rows with an explicit clock time and versus delimiter.
/// Every nonempty line must match. Richer descriptions remain the model's responsibility.
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
    for row in rows {
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
      fixtures.append(ExtractedFixture(
        source: row, firstTeam: first, secondTeam: second, time: String(row[timeRange])
      ))
    }
    return fixtures
  }
}
