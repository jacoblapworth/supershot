import Foundation

nonisolated enum ScoringPersistenceError: Error {
  case gameNotFound
  case goalUnavailable
}

nonisolated func resolvedCentrePassTeamID(_ teamID: Team.ID?, teamAID: Team.ID, teamBID: Team.ID)
  -> Team.ID
{
  GameScoringState(centrePassTeamID: teamID).centrePass(teamAID: teamAID, teamBID: teamBID)
}
