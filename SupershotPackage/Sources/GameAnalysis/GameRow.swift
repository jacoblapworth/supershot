import Database
import GameCore
import LocationClient
import PaywallFeature
import PreviewSupport
import SharedModels
import Styleguide
import SwiftUI
import WidgetSupport

package struct GameRow: View {
  package var game: GameListItem
  
  package var body: some View {
    VStack(spacing: 8) {
      HStack(alignment: .center, spacing: 12) {
        TeamScore(
          alignment: .leading,
          color: game.teamABibColor,
          name: game.teamAName,
          score: game.isPlanned ? nil : game.teamAScore,
          scoreColor: scoreColor(for: game.teamAScore, opponentScore: game.teamBScore)
        )
        TeamScore(
          alignment: .trailing,
          color: game.teamBBibColor,
          name: game.teamBName,
          score: game.isPlanned ? nil : game.teamBScore,
          scoreColor: scoreColor(for: game.teamBScore, opponentScore: game.teamAScore)
        )
      }
      
      HStack(spacing: 8) {
        Text(dateText)
          .foregroundStyle(.thickMaterial)
        
        if let court = game.court {
          Text("Court \(court)").foregroundStyle(.thickMaterial)
        }
        
        Spacer(minLength: 8)
        
        Label {
          if game.isPlanned {
            Text("Planned")
          } else if game.isCompleted {
            Text("Final")
          } else {
            Text("Q\(game.currentQuarter)")
          }
        } icon: {
          Image(
            systemName: game.isPlanned
              ? "calendar"
              : game.isCompleted
              ? "checkmark.circle.fill"
              : "clock.fill"
          )
        }
        .labelIconToTitleSpacing(4)
        .foregroundStyle(.thickMaterial)
      }
      .font(.caption.weight(.semibold))
    }
    .padding()
    .background {
//      MeshGradient(
//        width: 2,
//        height: 2,
//        bezierPoints: [
//          .init(
//            position: [0, 0],
//            leadingControlPoint: [0.0, 0.0],
//            topControlPoint: [0.0, 0.0],
//            trailingControlPoint: [0.0, 0.0],
//            bottomControlPoint: [0.0, 0.0]
//          ),
//          .init(
//            position: [0, 1],
//            leadingControlPoint: [0.0, 1.0],
//            topControlPoint: [0.0, 1.0],
//            trailingControlPoint: [0.0, 1.0],
//            bottomControlPoint: [0.0, 1.0]
//          ),
//          .init(
//            position: [1, 0],
//            leadingControlPoint: [1.0, 0.0],
//            topControlPoint: [1.0, 0.0],
//            trailingControlPoint: [1.0, 0.0],
//            bottomControlPoint: [1.0, 0.0]
//          ),
//          .init(
//            position: [1, 1],
//            leadingControlPoint: [1.0, 1.0],
//            topControlPoint: [1.0, 1.0],
//            trailingControlPoint: [1.0, 1.0],
//            bottomControlPoint: [1.0, 1.0]
//          ),
//        ],
//        colors: [
//          game.teamABibColor,
//          game.teamABibColor,
//          game.teamBBibColor,
//          game.teamBBibColor,
//        ]
//      )
//      MeshGradient(
//        width: 2,
//        height: 2,
//        points: [
//          [0.5, 0.5],
//          [0, 1],
//          [1, 0],
//          [1, 1]
//        ],
//        colors: [
//          game.teamABibColor,
//          game.teamABibColor,
//          game.teamBBibColor,
//          game.teamBBibColor,
//        ]
//      )
      LinearGradient(
        stops: [
          Gradient.Stop(color: game.teamABibColor, location: 0.2),
          Gradient.Stop(color: game.teamBBibColor, location: 0.8)
        ],
        startPoint: .leading,
        endPoint: .trailing
      )
    }
    .contentShape(.rect)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .listRowInsets(.all, 0)
  }
  
  private func scoreColor(for score: Int, opponentScore: Int) -> Color {
    guard game.isCompleted, score < opponentScore else { return .primary }
    return .secondary
  }
  
  private var dateText: String {
    if game.isPlanned {
      return game.scheduledAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unscheduled"
    }
    return game.startedAt?.formatted(date: .abbreviated, time: .shortened) ?? ""
  }
  
  private var accessibilityText: String {
    let date = dateText
    let court = game.court.map { ", Court \($0)" } ?? ""
    if game.isPlanned {
      return "\(date), \(game.teamAName), \(game.teamBName), Planned\(court), \(game.timingSummary)"
    }
    let status = game.isCompleted ? "Final" : "Q\(game.currentQuarter)"
    return "\(date), \(game.teamAName) \(game.teamAScore), "
      + "\(game.teamBName) \(game.teamBScore), \(status)\(court), \(game.timingSummary)"
  }
  
  package init(game: GameListItem) {
    self.game = game
  }
}

private struct TeamScore: View {
  var alignment: HorizontalAlignment
  var color: Color
  var name: String
  var score: Int?
  var scoreColor: Color
  
  var avatar: some View {
    AvatarView(name)
      .backgroundStyle(.ultraThinMaterial)
      .foregroundStyle(.ultraThickMaterial)
  }

  var body: some View {
    VStack(alignment: alignment, spacing: 4) {
      Text(name)
        .font(.headline)
        .lineLimit(1)
        .truncationMode(.middle)
        .multilineTextAlignment(.center)
        .foregroundStyle(.thickMaterial)
      HStack(spacing: 16) {
        if alignment == .leading {
          avatar
        }
        if let score {
          Text("\(score)")
            .font(.system(size: 62, weight: .bold))
            .fontWidth(.compressed)
            .monospacedDigit()
            .foregroundStyle(scoreColor)
        }
        if alignment == .trailing {
          avatar
        }
      }
    }
    .frame(
      maxWidth: .infinity,
      alignment: alignment == .leading ? .leading : .trailing
    )
  }
}

#Preview("List") {
  List {
    GameRow(game: .previewInProgress)
    GameRow(game: .previewCompleted)
  }
  .listRowSpacing(8)
}

#Preview("In-progress game") {
  GameRow(game: .previewInProgress)
}

#Preview("Completed game row") {
  GameRow(game: .previewCompleted)
}

#Preview("Loading game row") {
  GameRow(game: .previewInProgress)
}
