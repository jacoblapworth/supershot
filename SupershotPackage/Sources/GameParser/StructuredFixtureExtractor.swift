import Foundation
import OSLog

/// A conservative fast path for fixture rows with an explicit clock time and versus delimiter.
/// Inline metadata requires a column boundary (a tab or at least two whitespace characters).
/// Recognizes explicit league/date headers and division/court lines; unknown lines use the model.
nonisolated enum StructuredFixtureExtractor {
  static func extract(_ text: String) -> [ExtractedFixture]? {
    let rows = text.split(whereSeparator: \.isNewline).map(String.init)
      .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    guard !rows.isEmpty else { return nil }
    let column = #"(?:\t|[^\S\r\n]{2,})"#
    let labelValue = #"[\p{L}\p{N}-]+"#
    let rowPattern = #"^\s*((?:[01]?[0-9]|2[0-3]):[0-5][0-9])\s+"#
      + #"(?:(?i:(Division\s+"# + labelValue + #"))"# + column + #")?"#
      + #"(.+?)\s+(?i:vs?\.?)\s+(.+?)"#
      + #"(?:"# + column + #"(?i:(Court\s+"# + labelValue + #")))?\s*$"#
    let separatorPattern = #"(?i)\s+vs?\.?\s+"#
    // Do not consume metadata, a second fixture, or natural-language scheduling as a team name.
    let metadataPattern = #"(?i)\b(court|division|today|tomorrow|yesterday|tonight|next|monday|tuesday|wednesday|thursday|friday|saturday|sunday|at|on)\b|[0-9]{1,2}:[0-9]{2}|[0-9]+[-/][0-9]+"#
    guard let rowRegex = try? NSRegularExpression(pattern: rowPattern),
          let separatorRegex = try? NSRegularExpression(pattern: separatorPattern),
          let metadataRegex = try? NSRegularExpression(pattern: metadataPattern)
    else { return nil }
    func fallback(_ reason: String, line: Int = 0) -> [ExtractedFixture]? {
      GameParserDiagnostics.logger.info("[\(GameParserDiagnostics.requestID, privacy: .public)] Structured fallback: reason=\(reason, privacy: .public) line=\(line)")
      return nil
    }
    var fixtures: [ExtractedFixture] = []
    var sharedDate: String?
    var pendingHeader = false
    var cursor = text.startIndex
    var fixtureStart: String.Index?
    for row in rows {
      guard let rowRange = text.range(of: row, range: cursor ..< text.endIndex) else { return nil }
      cursor = rowRange.upperBound
      let line = text[..<rowRange.lowerBound].unicodeScalars.filter { $0 == "\n" }.count + 1
      let trimmed = row.trimmingCharacters(in: .whitespaces)
      if trimmed.range(of: #"(?i)^league name\s*:"#, options: .regularExpression) != nil {
        guard fixtures.isEmpty else { return fallback("league_header_after_fixture", line: line) }
        pendingHeader = true
        continue
      }
      if trimmed.range(of: #"^(?:(?i:mon|tue|wed|thu|fri|sat|sun)\s+)?(?:[0-9]{2}/[0-9]{2}/[0-9]{4}|[0-9]{4}-[0-9]{2}-[0-9]{2})$"#, options: .regularExpression) != nil {
        sharedDate = trimmed.split(whereSeparator: \.isWhitespace).last.map(String.init)
        pendingHeader = true
        continue
      }
      if trimmed.range(of: #"(?i)^division\s+.+?\s*[•·]\s*court\s+.+$"#, options: .regularExpression) != nil {
        guard !fixtures.isEmpty, !pendingHeader else { return fallback("orphan_metadata", line: line) }
        let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: "•·"))
        // Keep the actual contiguous source, including blank lines.
        guard let fixtureStart, fixtures[fixtures.count - 1].division == nil, fixtures[fixtures.count - 1].court == nil else { return fallback("duplicate_metadata", line: line) }
        fixtures[fixtures.count - 1].source = String(text[fixtureStart ..< rowRange.upperBound])
        fixtures[fixtures.count - 1].division = parts[0].trimmingCharacters(in: .whitespaces)
        fixtures[fixtures.count - 1].court = parts[1].trimmingCharacters(in: .whitespaces)
        continue
      }
      let range = NSRange(row.startIndex..., in: row)
      guard separatorRegex.numberOfMatches(in: row, range: range) == 1,
            let match = rowRegex.firstMatch(in: row, range: range),
            let timeRange = Range(match.range(at: 1), in: row),
            let firstRange = Range(match.range(at: 3), in: row),
            let secondRange = Range(match.range(at: 4), in: row)
      else { return fallback("unrecognized_or_ambiguous_row", line: line) }
      let first = String(row[firstRange])
      let second = String(row[secondRange])
      guard !first.trimmingCharacters(in: .whitespaces).isEmpty,
            !second.trimmingCharacters(in: .whitespaces).isEmpty else { return fallback("empty_team", line: line) }
      for name in [first, second] {
        guard metadataRegex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) == nil
        else { return fallback("metadata_in_team", line: line) }
      }
      fixtures.append(ExtractedFixture(
        source: row,
        firstTeam: first,
        secondTeam: second,
        date: sharedDate,
        time: String(row[timeRange]),
        division: Range(match.range(at: 2), in: row).map { String(row[$0]) },
        court: Range(match.range(at: 5), in: row).map { String(row[$0]) }
      ))
      pendingHeader = false
      fixtureStart = rowRange.lowerBound
    }
    guard !pendingHeader else { return fallback("header_without_fixture") }
    return fixtures
  }
}
