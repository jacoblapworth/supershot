import Database
import Foundation
import GameCore
import SharedModels
import SwiftUI
import UI

package extension GameRow {
  init(game: GameListItem) {
    let status: Status = if game.isCompleted {
      .final
    } else if game.isPlanned {
      .planned(game.scheduledAt)
    } else {
      .inProgress(quarter: game.currentQuarter)
    }

    var details = [game.timingSummary]
    if let court = game.court {
      details.append(String(localized: "Court \(court)"))
    }
    if let startedAt = game.startedAt {
      details.append(startedAt.formatted(date: .abbreviated, time: .shortened))
    }
    if game.isPlanned, game.scheduledAt == nil {
      details.append(String(localized: "Draft"))
    }

    self.init(
      teamA: .init(name: game.teamAName, colorHex: game.teamABibColorHex, logoData: game.teamALogoData, score: game.teamAScore),
      teamB: .init(name: game.teamBName, colorHex: game.teamBBibColorHex, logoData: game.teamBLogoData, score: game.teamBScore),
      status: status,
      background: .gradient,
      layout: .standard,
      accessibilityDetails: details.filter { !$0.isEmpty }.joined(separator: ", "),
      clock: { date in
        game.clockDisplay(at: date).map {
          Clock(quarter: $0.period, isBreak: $0.isBreak, remainingSeconds: $0.remainingSeconds)
        }
      }
    )
  }
}

private enum GameRowPreviewData {
  static func game(state: Int, longNames: Bool = false, tied: Bool = false) -> GameListItem {
    let now = Date.now
    let id = UUID()
    return GameListItem(
      endedAt: state == 3 ? now : nil,
      id: id,
      periods: [.init(id: UUID(), gameID: id, position: 0, durationSeconds: 900)],
      startedAt: state >= 2 ? now : nil,
      teamABibColorHex: "#FF9A00",
      teamAName: longNames ? "North London Hackney Foxes" : "Hackney Foxes",
      teamAScore: longNames ? 118 : 18,
      teamBBibColorHex: "#FF2729",
      teamBName: longNames ? "Camden Town Netball Owls" : "Camden Owls",
      teamBScore: tied ? 18 : 24,
      scheduledAt: state == 1 ? now : nil,
      timing: .init(phaseIndex: 0, countdown: .init(endsAt: now.addingTimeInterval(89)))
    )
  }
}

#Preview("Figma game rows") {
  VStack(spacing: 8) {
    ForEach(0 ..< 4) { state in
      GameRow(game: GameRowPreviewData.game(state: state))
    }
  }
  .padding(16)
  .frame(width: 402)
}

#Preview("Long names and scores") {
  List {
    GameRow(game: GameRowPreviewData.game(state: 2, longNames: true))
    GameRow(game: GameRowPreviewData.game(state: 3, tied: true))
  }
}

#Preview("Accessibility text") {
  List {
    GameRow(game: GameRowPreviewData.game(state: 2, longNames: true))
    GameRow(game: GameRowPreviewData.game(state: 1))
  }
  .environment(\.dynamicTypeSize, .accessibility2)
}
