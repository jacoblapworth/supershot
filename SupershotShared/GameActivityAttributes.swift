#if os(iOS)
import ActivityKit
import Foundation
import SwiftUI

nonisolated struct GameActivityAttributes: ActivityAttributes {
  nonisolated struct ContentState: Codable, Hashable, Sendable {
    var centrePassTeamID: UUID
    var currentDurationSeconds: Int
    var elapsedSeconds: Int
    var phaseIndex: Int
    var teamAScore: Int
    var teamBScore: Int
    var timerEndsAt: Date?
  }

  var gameID: UUID
  var teamAID: UUID
  var teamAColorHex: String
  var teamAName: String
  var teamBID: UUID
  var teamBColorHex: String
  var teamBName: String
}

nonisolated extension GameActivityAttributes {
  var teamAColor: Color { Color(hex: teamAColorHex) }
  var teamBColor: Color { Color(hex: teamBColorHex) }
}
#endif
