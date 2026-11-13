import Database
import Foundation
import GameCore
import SharedModels
import SwiftUI
import UI

package struct GameRow: View {
  package var game: GameListItem
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  package var body: some View {
    VStack(spacing: 8) {
      HStack(alignment: .top, spacing: 16) {
        Text(game.teamAName)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(game.teamBName)
          .multilineTextAlignment(.trailing)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .font(.subheadline)
      .fontWeight(.semibold)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityHidden(!game.isPlanned)

      HStack(spacing: 16) {
        avatar(game.teamAName, colorHex: game.teamABibColorHex, logoData: game.teamALogoData)
        ViewThatFits(in: .horizontal) {
          scoreBar
          VStack(spacing: 8) {
            GameRowStatus(game: game)
            if !game.isPlanned {
              ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                  score(game.teamAScore, opponent: game.teamBScore, name: game.teamAName)
                  score(game.teamBScore, opponent: game.teamAScore, name: game.teamBName)
                }
                .fixedSize()
                VStack(spacing: 4) {
                  score(game.teamAScore, opponent: game.teamBScore, name: game.teamAName)
                  score(game.teamBScore, opponent: game.teamAScore, name: game.teamBName)
                }
              }
            }
          }
        }
        .frame(maxWidth: .infinity)
        avatar(game.teamBName, colorHex: game.teamBBibColorHex, logoData: game.teamBLogoData)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .foregroundStyle(.white)
    .background {
      LinearGradient(
        colors: [Color(hex: game.teamABibColorHex), Color(hex: game.teamBBibColorHex)],
        startPoint: .leading,
        endPoint: .trailing
      )
    }
    .clipShape(.rect(cornerRadius: 24))
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
    .accessibilityValue(Text(accessibilityDetails))
    .listRowInsets(.all, 0)
    .listRowBackground(Color.clear)
  }

  private var scoreBar: some View {
    HStack(spacing: 12) {
      if !game.isPlanned {
        score(game.teamAScore, opponent: game.teamBScore, name: game.teamAName)
      }
      Spacer(minLength: 0)
      GameRowStatus(game: game)
        .fixedSize()
      Spacer(minLength: 0)
      if !game.isPlanned {
        score(game.teamBScore, opponent: game.teamAScore, name: game.teamBName)
      }
    }
    .fixedSize(horizontal: dynamicTypeSize.isAccessibilitySize, vertical: false)
  }

  private func avatar(_ name: String, colorHex: String, logoData: Data?) -> some View {
    AvatarView(name, initialsFont: .system(.subheadline, design: .rounded, weight: .bold), borderOpacity: 0.22, logoData: logoData)
      .controlSize(.regular)
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      .backgroundStyle(Color(hex: colorHex))
      .accessibilityHidden(true)
  }

  private func score(_ value: Int, opponent: Int, name: String) -> some View {
    Text(value, format: .number)
      .font(.largeTitle)
      .fontWidth(.compressed)
      .fontWeight(.semibold)
      .foregroundStyle(.white.opacity(game.isCompleted && value < opponent ? 0.7 : 1))
      .fixedSize()
      .accessibilityLabel(Text("\(name), \(value)"))
  }

  private var accessibilityDetails: String {
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
    return details.filter { !$0.isEmpty }.joined(separator: ", ")
  }

  package init(game: GameListItem) {
    self.game = game
  }
}

private struct GameRowStatus: View {
  let game: GameListItem

  var body: some View {
    if game.isCompleted {
      Text("Final")
        .font(.body)
    } else if game.isPlanned {
      if let scheduledAt = game.scheduledAt {
        TimelineView(.everyMinute) { context in
          VStack(spacing: 0) {
            Text(scheduledAt, format: .dateTime.hour().minute())
              .font(.body)
            Text(dayText(scheduledAt, now: context.date))
              .font(.caption)
          }
          .multilineTextAlignment(.center)
        }
      }
    } else {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        VStack(spacing: 0) {
          if let clock = game.clockDisplay(at: context.date) {
            if clock.isBreak {
              Text("Break")
            } else {
              Text("Q\(clock.period)")
            }
            Text(Duration.seconds(clock.remainingSeconds), format: .time(pattern: .minuteSecond))
              .font(.caption.monospacedDigit())
          } else {
            Text("Q\(game.currentQuarter)")
          }
        }
        .font(.body)
        .multilineTextAlignment(.center)
      }
    }
  }

  private func dayText(_ date: Date, now: Date) -> String {
    let calendar = Calendar.autoupdatingCurrent
    if calendar.isDate(date, inSameDayAs: now) {
      return String(localized: "Today")
    }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
       calendar.isDate(date, inSameDayAs: tomorrow)
    {
      return String(localized: "Tomorrow")
    }
    return date.formatted(date: .abbreviated, time: .omitted)
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
