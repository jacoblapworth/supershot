import Foundation
import GameCore
import GameParser

/// A batch owns one shared review entry per normalized name, in first-occurrence order.
/// Proposed identities are comparison keys, not allocated database IDs.
package nonisolated struct FixtureTeamReview: Equatable, Sendable {
  package private(set) var fixtures: [FixtureDraft]
  package private(set) var references: [References]
  package private(set) var entries: [Entry] = []
  private let savedTeams: [Team]

  package init(fixtures: [FixtureDraft], savedTeams: [Team]) {
    self.fixtures = fixtures
    self.savedTeams = savedTeams
    references = []
    for fixture in fixtures {
      let first = add(fixture.firstTeam)
      let second = add(fixture.secondTeam)
      references.append(References(first: first, second: second))
    }
  }

  package nonisolated enum Side: Sendable {
    case first
    case second
  }

  package nonisolated struct References: Equatable, Sendable {
    package var first: String?
    package var second: String?
  }

  package nonisolated enum Selection: Equatable, Sendable {
    case existing(Team.ID)
    case proposed
  }

  package nonisolated struct Entry: Equatable, Identifiable, Sendable {
    package let id: String
    /// Original spelling from the first occurrence, preserved for presentation.
    package let name: String
    package let resolution: TeamNameResolution
    package fileprivate(set) var selection: Selection?
  }

  /// Selecting an existing team or choosing a new proposal applies to every reference.
  package mutating func select(_ selection: Selection?, for key: String) throws {
    guard let index = entries.firstIndex(where: { $0.id == key }) else {
      throw ValidationError.unknownReference
    }
    if case let .existing(id) = selection, !savedTeams.contains(where: { $0.id == id }) {
      throw ValidationError.savedTeamUnavailable(id)
    }
    entries[index].selection = selection
  }

  /// Edits are occurrence-specific. Any previous selection is discarded, even when
  /// the edited spelling has the same comparison key. Repeated references stay shared.
  package mutating func editName(_ name: String?, fixture index: Int, side: Side) {
    switch side {
    case .first: fixtures[index].firstTeam = name
    case .second: fixtures[index].secondTeam = name
    }
    let editedKey = name.map(FixtureTeamResolver.key(for:))
    var updated = Self(fixtures: fixtures, savedTeams: savedTeams)
    for index in updated.entries.indices {
      let key = updated.entries[index].id
      updated.entries[index].selection = key == editedKey
        ? nil
        : entries.first(where: { $0.id == key })?.selection
    }
    self = updated
  }

  /// Call with a fresh snapshot INSIDE the eventual import transaction, before writes.
  /// This validates team identities only; parser/metadata issues remain the caller's responsibility.
  package func validatedTeams(currentTeams: [Team]) throws -> [ResolvedFixtureTeams] {
    try references.map { reference in
      let first = try identity(for: reference.first, currentTeams: currentTeams)
      let second = try identity(for: reference.second, currentTeams: currentTeams)
      guard first != second else { throw ValidationError.sameTeam }
      return ResolvedFixtureTeams(first: first, second: second)
    }
  }

  package nonisolated enum ValidationError: Error, Equatable, Sendable {
    case unknownReference
    case missingName
    case reviewRequired(String)
    case savedTeamUnavailable(Team.ID)
    case savedTeamRenamed(Team.ID)
    case sameTeam
  }

  private mutating func add(_ name: String?) -> String? {
    guard let name else { return nil }
    let key = FixtureTeamResolver.key(for: name)
    guard !key.isEmpty else { return nil }
    guard !entries.contains(where: { $0.id == key }) else { return key }
    let resolution = FixtureTeamResolver(teams: savedTeams).resolve(name)
    let selection: Selection? = switch resolution {
    case let .unique(id, _): .existing(id)
    case .ambiguous: nil
    case .unmatched: .proposed
    }
    entries.append(Entry(id: key, name: name, resolution: resolution, selection: selection))
    return key
  }

  private func identity(for key: String?, currentTeams: [Team]) throws -> ResolvedTeamIdentity {
    guard let key else { throw ValidationError.missingName }
    guard let entry = entries.first(where: { $0.id == key }) else {
      throw ValidationError.unknownReference
    }
    switch entry.selection {
    case let .existing(id):
      guard let current = currentTeams.first(where: { $0.id == id }) else {
        throw ValidationError.savedTeamUnavailable(id)
      }
      guard let original = savedTeams.first(where: { $0.id == id }),
            FixtureTeamResolver.key(for: current.name) == FixtureTeamResolver.key(for: original.name)
      else { throw ValidationError.savedTeamRenamed(id) }
      return .existing(id)
    case .proposed:
      return .proposed(key: key)
    case nil:
      throw ValidationError.reviewRequired(key)
    }
  }
}

package nonisolated enum ResolvedTeamIdentity: Equatable, Sendable {
  case existing(Team.ID)
  /// Look up the display name in the batch entry and allocate one ID per key at commit.
  case proposed(key: String)
}

package nonisolated struct ResolvedFixtureTeams: Equatable, Sendable {
  package var first: ResolvedTeamIdentity
  package var second: ResolvedTeamIdentity
}
