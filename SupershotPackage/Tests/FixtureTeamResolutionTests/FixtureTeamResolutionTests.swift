@testable import FixtureTeamResolution
import Foundation
import GameCore
@testable import GameParser
import Testing

struct FixtureTeamResolutionTests {
  private let buzz = Team(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Buzz Ballers")
  private let chill = Team(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Netball & Chill")

  private func fixture(_ first: String?, _ second: String?) -> FixtureDraft {
    FixtureDraft(source: "original", sourceLine: 1, firstTeam: first, secondTeam: second, issues: [])
  }

  @Test(arguments: ["Buzz Ballers", "BUZZ BALLERS", "Búzz Bällers", " \tBuzz\n Ballers \u{00A0}"])
  func exactVariants(name: String) {
    let result = FixtureTeamResolver(teams: [buzz]).resolve(name)
    guard case let .unique(id, candidates) = result else {
      Issue.record("Expected unique exact match")
      return
    }
    #expect(id == buzz.id)
    #expect(candidates.first?.isExact == true)
    #expect(candidates.first?.team.name == "Buzz Ballers")
  }

  @Test func exactBeforeFuzzyAndStableAcrossSnapshotOrder() {
    let similar = Team(id: UUID(), name: "Buzz Ballerz")
    let first = FixtureTeamResolver(teams: [similar, buzz]).resolve("Buzz Ballers")
    #expect(first == FixtureTeamResolver(teams: [buzz, similar]).resolve("Buzz Ballers"))
    #expect(first.candidates.map(\.team.id) == [buzz.id, similar.id])
    #expect(first.candidates.first?.isExact == true)
  }

  @Test func fuzzyCandidatesNeverAutoSelectOrMergeNames() throws {
    let resolver = FixtureTeamResolver(teams: [buzz])
    guard case let .ambiguous(candidates) = resolver.resolve("Buzz Ballerz") else {
      Issue.record("Expected fuzzy suggestion")
      return
    }
    #expect(candidates.map(\.team.id) == [buzz.id])
    var review = FixtureTeamReview(fixtures: [fixture("Buzz Ballerz", "Buzz Ballers")], savedTeams: [buzz])
    #expect(review.entries.count == 2)
    #expect(review.entries[0].selection == nil)
    #expect(throws: FixtureTeamReview.ValidationError.reviewRequired("buzz ballerz")) {
      try review.validatedTeams(currentTeams: [buzz])
    }
    try review.select(.proposed, for: "buzz ballerz")
    #expect(try review.validatedTeams(currentTeams: [buzz])[0].first == .proposed(key: "buzz ballerz"))
  }

  @Test func tiesAndDuplicateSavedNamesStayAmbiguous() throws {
    let duplicate = try Team(id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003")), name: "Búzz Ballers")
    for name in ["Buzz Ballers", "Buzz Ballerz"] {
      let result = FixtureTeamResolver(teams: [duplicate, buzz]).resolve(name)
      guard case let .ambiguous(candidates) = result else {
        Issue.record("Duplicates and tied fuzzy scores require review")
        continue
      }
      #expect(candidates.map(\.team.id) == [buzz.id, duplicate.id])
      #expect(candidates[0].score == candidates[1].score)
      #expect(result == FixtureTeamResolver(teams: [buzz, duplicate]).resolve(name))
    }
  }

  @Test func punctuationAndUnmatchedNames() {
    let resolver = FixtureTeamResolver(teams: [chill])
    #expect(resolver.resolve("ZXQ Wanderers") == .unmatched)
    #expect(resolver.resolve("  \n") == .unmatched)
    #expect(FixtureTeamResolver.key(for: "Netball & Chill") != FixtureTeamResolver.key(for: "Netball Chill"))
    #expect(FixtureTeamResolver.key(for: "One Team, One Dream") == "one team, one dream")
    if case .unique = resolver.resolve("Netball Chill") {
      Issue.record("Punctuation differences must never auto-select")
    }
  }

  @Test func sampleSharesRepeatedProposalsAndPreservesDisplayNames() throws {
    let pairs = [
      ("Coles Hot Chooks", "IMG & Friends"),
      ("Mixed Bag", "Buzz Ballers"),
      ("Buzz Ballers", "Clapham Ballers"),
      ("Pole vaulters", "Silence of the Lambeths"),
      ("The lodgers", "Netball & Chill"),
      ("Netball & Chill", "One Team, One Dream"),
    ]
    let drafts = pairs.map { fixture($0.0, $0.1) }
    let review = FixtureTeamReview(fixtures: drafts, savedTeams: [])
    #expect(review.fixtures == drafts)
    #expect(review.entries.count == 10)
    #expect(review.entries.map(\.name).contains("One Team, One Dream"))
    #expect(review.entries.allSatisfy { $0.selection == .proposed })
    let teams = try review.validatedTeams(currentTeams: [])
    #expect(teams[1].second == teams[2].first)
    #expect(teams[4].second == teams[5].first)
  }

  @Test func repeatedVariantsShareSelections() throws {
    var review = FixtureTeamReview(fixtures: [fixture("Buzz Ballerz", "Other"), fixture("Third", "BÚZZ  BALLERZ")], savedTeams: [buzz])
    #expect(review.references[0].first == review.references[1].second)
    try review.select(.existing(buzz.id), for: "buzz ballerz")
    let teams = try review.validatedTeams(currentTeams: [buzz])
    #expect(teams[0].first == .existing(buzz.id))
    #expect(teams[1].second == .existing(buzz.id))
  }

  @Test func rejectsSameExistingAndProposedIdentities() throws {
    var review = FixtureTeamReview(fixtures: [fixture("Buzz Ballers", "Buzz Ballerz")], savedTeams: [buzz])
    try review.select(.existing(buzz.id), for: "buzz ballerz")
    #expect(throws: FixtureTeamReview.ValidationError.sameTeam) {
      try review.validatedTeams(currentTeams: [buzz])
    }
    let proposed = FixtureTeamReview(fixtures: [fixture("New Team", "NEW  TÉAM")], savedTeams: [])
    #expect(throws: FixtureTeamReview.ValidationError.sameTeam) {
      try proposed.validatedTeams(currentTeams: [])
    }
  }

  @Test func editsInvalidateSelectionsAndRecomputeMatches() throws {
    var review = FixtureTeamReview(fixtures: [fixture("Buzz Ballers", "Other")], savedTeams: [buzz, chill])
    review.editName("Netball & Chill", fixture: 0, side: .first)
    let entry = try #require(review.entries.first(where: { $0.id == "netball & chill" }))
    #expect(entry.selection == nil)
    #expect(entry.resolution.candidates.first?.team.id == chill.id)
    #expect(!review.entries.contains(where: { $0.id == "buzz ballers" }))
    #expect(throws: FixtureTeamReview.ValidationError.reviewRequired(entry.id)) {
      try review.validatedTeams(currentTeams: [buzz, chill])
    }
    try review.select(.existing(chill.id), for: entry.id)
    review.editName("NETBALL & CHILL", fixture: 0, side: .first)
    #expect(review.entries.first(where: { $0.id == entry.id })?.selection == nil)
  }

  @Test func editingOneRepeatedReferenceKeepsOthersAndClearsDestinationChoice() {
    var review = FixtureTeamReview(fixtures: [fixture("Buzz Ballers", "Other"), fixture("Third", "Buzz Ballers")], savedTeams: [buzz, chill])
    review.editName("Netball & Chill", fixture: 0, side: .first)
    #expect(review.references[1].second == "buzz ballers")
    #expect(review.entries.first(where: { $0.id == "buzz ballers" })?.selection == .existing(buzz.id))
    review.editName("BUZZ BALLERS", fixture: 0, side: .first)
    #expect(review.entries.first(where: { $0.id == "buzz ballers" })?.selection == nil)
  }

  @Test func editedProposalUsesCorrectedDisplaySpelling() throws {
    var review = FixtureTeamReview(fixtures: [fixture("new team", "Other")], savedTeams: [])
    review.editName("Néw Team", fixture: 0, side: .first)
    #expect(review.entries[0].name == "Néw Team")
    #expect(review.entries[0].selection == nil)
    try review.select(.proposed, for: "new team")
    #expect(try review.validatedTeams(currentTeams: [])[0].first == .proposed(key: "new team"))
  }

  @Test func missingNamesAndStaleIDsPreventCommit() throws {
    let missing = FixtureTeamReview(fixtures: [fixture(nil, "Other")], savedTeams: [])
    #expect(throws: FixtureTeamReview.ValidationError.missingName) {
      try missing.validatedTeams(currentTeams: [])
    }
    var review = FixtureTeamReview(fixtures: [fixture("Buzz Ballers", "Other")], savedTeams: [buzz])
    #expect(throws: FixtureTeamReview.ValidationError.savedTeamUnavailable(buzz.id)) {
      try review.validatedTeams(currentTeams: [])
    }
    var renamed = buzz
    renamed.name = "Different identity"
    #expect(throws: FixtureTeamReview.ValidationError.savedTeamRenamed(buzz.id)) {
      try review.validatedTeams(currentTeams: [renamed])
    }
    #expect(throws: FixtureTeamReview.ValidationError.savedTeamUnavailable(chill.id)) {
      try review.select(.existing(chill.id), for: "other")
    }
  }
}
