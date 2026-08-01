#if os(iOS)
import ActivityKit
import Foundation

nonisolated struct GameActivityAttributes: ActivityAttributes {
  nonisolated struct ContentState: Codable, Hashable, Sendable {
    var currentDurationSeconds: Int
    var elapsedSeconds: Int
    var isInBreak: Bool
    var period: Int
    var teamAScore: Int
    var teamBScore: Int
    var timerEndsAt: Date?
  }

  var gameID: UUID
  var teamAColorHex: String
  var teamAName: String
  var teamBColorHex: String
  var teamBName: String
}
#endif
