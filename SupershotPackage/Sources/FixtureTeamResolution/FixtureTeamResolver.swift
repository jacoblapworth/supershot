import Foundation
import FuzzyMatch
import GameCore

/// Pure matching over a caller-supplied snapshot. Never reads or writes the database.
package nonisolated struct FixtureTeamResolver: Sendable {
  private let teams: [Team]

  package init(teams: [Team]) {
    self.teams = teams
  }

  /// Locale-independent comparison key; punctuation is intentionally significant.
  package static func key(for name: String) -> String {
    name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
  }

  package func resolve(_ name: String) -> TeamNameResolution {
    let key = Self.key(for: name)
    guard !key.isEmpty else { return .unmatched }
    let matcher = FuzzyMatcher(config: MatchConfig(minScore: 0.7))
    let query = matcher.prepare(key)
    var buffer = matcher.makeBuffer()
    let candidates = teams.compactMap { team -> TeamMatchCandidate? in
      let candidateKey = Self.key(for: team.name)
      if key == candidateKey {
        return TeamMatchCandidate(team: team, isExact: true, score: 1)
      }
      guard let match = matcher.score(candidateKey, against: query, buffer: &buffer) else {
        return nil
      }
      return TeamMatchCandidate(team: team, isExact: false, score: match.score)
    }.sorted {
      if $0.isExact != $1.isExact {
        return $0.isExact
      }
      if $0.score != $1.score {
        return $0.score > $1.score
      }
      let lhs = Self.key(for: $0.team.name)
      let rhs = Self.key(for: $1.team.name)
      if lhs != rhs {
        return lhs < rhs
      }
      return $0.team.id.uuidString < $1.team.id.uuidString
    }
    let exact = candidates.filter(\.isExact)
    if exact.count == 1 {
      return .unique(exact[0].team.id, candidates: candidates)
    }
    if !candidates.isEmpty {
      return .ambiguous(candidates)
    }
    return .unmatched
  }
}

package nonisolated struct TeamMatchCandidate: Equatable, Sendable {
  package var team: Team
  package var isExact: Bool
  /// Ranking score from the library, never model confidence or an identity decision.
  package var score: Double
}

package nonisolated enum TeamNameResolution: Equatable, Sendable {
  /// Only one normalized exact saved-team match may be automatically selected.
  case unique(Team.ID, candidates: [TeamMatchCandidate])
  /// Includes a single fuzzy candidate. Callers decide how to apply these suggestions.
  case ambiguous([TeamMatchCandidate])
  case unmatched

  package var candidates: [TeamMatchCandidate] {
    switch self {
    case let .unique(_, candidates), let .ambiguous(candidates): candidates
    case .unmatched: []
    }
  }
}
