import Foundation
import SwiftUI
import WidgetSupport

public struct GameRow: View {
  package enum Background { case gradient, clear }
  public enum Layout { case standard, compact, stacked }

  package struct Team {
    var name: String
    var colorHex: String
    var logoData: Data?
    var score: Int

    package init(name: String, colorHex: String, logoData: Data?, score: Int) {
      self.name = name
      self.colorHex = colorHex
      self.logoData = logoData
      self.score = score
    }
  }

  package enum Status: Equatable {
    case planned(Date?)
    case inProgress(quarter: Int)
    case final
  }

  package struct Clock {
    var quarter: Int
    var isBreak: Bool
    var remainingSeconds: Int

    package init(quarter: Int, isBreak: Bool, remainingSeconds: Int) {
      self.quarter = quarter
      self.isBreak = isBreak
      self.remainingSeconds = remainingSeconds
    }
  }

  private let teamA: Team
  private let teamB: Team
  private let status: Status
  private let backgroundStyle: Background
  private let layout: Layout
  private let accessibilityDetails: String
  private let clock: ((Date) -> Clock?)?

  package init(
    teamA: Team,
    teamB: Team,
    status: Status,
    background: Background,
    layout: Layout,
    accessibilityDetails: String = "",
    clock: ((Date) -> Clock?)? = nil
  ) {
    self.teamA = teamA
    self.teamB = teamB
    self.status = status
    backgroundStyle = background
    self.layout = layout
    self.accessibilityDetails = accessibilityDetails
    self.clock = clock
  }

  public init(widgetGame game: WidgetGame, layout: Layout) {
    let status: Status = if game.isCompleted {
      .final
    } else if game.isPlanned {
      .planned(game.scheduledAt)
    } else {
      .inProgress(quarter: game.period)
    }
    self.init(
      teamA: .init(name: game.teamAName, colorHex: game.teamAColorHex, logoData: game.teamALogoData, score: game.teamAScore),
      teamB: .init(name: game.teamBName, colorHex: game.teamBColorHex, logoData: game.teamBLogoData, score: game.teamBScore),
      status: status,
      background: .clear,
      layout: layout
    )
  }

  private var spacing: CGFloat {
    layout == .standard ? 8 : 4
  }

  private var showsScores: Bool {
    if case .planned = status {
      return false
    }
    return true
  }

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public var body: some View {
    Group {
      switch layout {
      case .standard, .compact: horizontalRow
      case .stacked: stackedRow
      }
    }
    .padding(.horizontal, layout == .standard ? 16 : 8)
    .padding(.vertical, layout == .standard ? 12 : 4)
    .foregroundStyle(backgroundStyle == .gradient ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    .background {
      if backgroundStyle == .gradient {
        LinearGradient(
          colors: [Color(hex: teamA.colorHex), Color(hex: teamB.colorHex)],
          startPoint: .leading,
          endPoint: .trailing
        )
        .clipShape(.rect(cornerRadius: 24))
      }
    }
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
    .accessibilityValue(Text(accessibilityDetails))
    .listRowInsets(.all, 0)
    .listRowBackground(Color.clear)
  }

  private var horizontalRow: some View {
    VStack(spacing: spacing) {
      HStack(alignment: .top, spacing: spacing * 2) {
        teamName(teamA)
          .frame(maxWidth: .infinity, alignment: .leading)
        teamName(teamB)
          .multilineTextAlignment(.trailing)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .accessibilityHidden(showsScores)

      HStack(spacing: spacing * 2) {
        avatar(teamA)
        ViewThatFits(in: .horizontal) {
          scoreBar
          if layout == .standard {
            standardScoreFallback
          }
        }
        .frame(maxWidth: .infinity)
        avatar(teamB)
      }
    }
  }

  private var standardScoreFallback: some View {
    VStack(spacing: 8) {
      statusView
      if showsScores {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 8) {
            score(teamA.score, opponent: teamB.score, name: teamA.name)
            score(teamB.score, opponent: teamA.score, name: teamB.name)
          }
          .fixedSize()
          VStack(spacing: 4) {
            score(teamA.score, opponent: teamB.score, name: teamA.name)
            score(teamB.score, opponent: teamA.score, name: teamB.name)
          }
        }
      }
    }
  }

  private var scoreBar: some View {
    HStack(spacing: layout == .standard ? 12 : 4) {
      if showsScores {
        score(teamA.score, opponent: teamB.score, name: teamA.name)
      }
      Spacer(minLength: 0)
      statusView
        .fixedSize()
      Spacer(minLength: 0)
      if showsScores {
        score(teamB.score, opponent: teamA.score, name: teamB.name)
      }
    }
    .fixedSize(horizontal: dynamicTypeSize.isAccessibilitySize, vertical: false)
  }

  private func avatar(_ team: Team) -> some View {
    AvatarView(
      team.name,
      initialsFont: layout == .standard ? .system(.subheadline, design: .rounded, weight: .bold) : nil,
      borderOpacity: 0.22,
      logoData: team.logoData
    )
    .synchronousLogoDecoding(backgroundStyle == .clear)
    .controlSize(layout == .standard ? .regular : layout == .compact ? .mini : .small)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .backgroundStyle(Color(hex: team.colorHex))
    .foregroundStyle(.white)
    .accessibilityHidden(true)
  }

  private func score(_ value: Int, opponent: Int, name: String) -> some View {
    Text(value, format: .number)
      .font(layout == .standard ? .largeTitle : .title2)
      .fontWidth(.compressed)
      .fontWeight(.semibold)
      .opacity(status == .final && value < opponent ? 0.7 : 1)
      .fixedSize()
      .accessibilityLabel(Text("\(name), \(value)"))
  }

  private var stackedRow: some View {
    VStack(spacing: 4) {
      stackedTeam(teamA, opponent: teamB)
      Spacer(minLength: 0)
      statusView
      Spacer(minLength: 0)
      stackedTeam(teamB, opponent: teamA)
    }
  }

  private func stackedTeam(_ team: Team, opponent: Team) -> some View {
    HStack(spacing: 6) {
      avatar(team)
      teamName(team)
        .accessibilityHidden(showsScores)
      Spacer(minLength: 0)
      if showsScores {
        score(team.score, opponent: opponent.score, name: team.name)
      }
    }
  }

  private func teamName(_ team: Team) -> some View {
    Text(team.name)
      .font(layout == .standard ? .subheadline : .caption)
      .fontWeight(.semibold)
      .lineLimit(layout == .standard ? nil : 2)
      .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder private var statusView: some View {
    switch status {
    case .final:
      Text("Final")
        .font(statusFont)
    case let .planned(scheduledAt):
      if let scheduledAt {
        if backgroundStyle == .clear {
          // A widget entry can stay visible across midnight.
          schedule(scheduledAt, day: scheduledAt.formatted(date: .abbreviated, time: .omitted))
        } else {
          TimelineView(.everyMinute) { context in
            schedule(scheduledAt, day: dayText(scheduledAt, now: context.date))
          }
        }
      } else if layout != .standard {
        Text("Draft")
          .font(statusFont)
      }
    case let .inProgress(quarter):
      if let clock {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          VStack(spacing: 0) {
            if let display = clock(context.date) {
              if display.isBreak {
                Text("Break")
              } else {
                quarterLabel(display.quarter)
              }
              Text(Duration.seconds(display.remainingSeconds), format: .time(pattern: .minuteSecond))
                .font(.caption.monospacedDigit())
            } else {
              quarterLabel(quarter)
            }
          }
          .font(statusFont)
          .multilineTextAlignment(.center)
        }
      } else {
        quarterLabel(quarter)
          .font(statusFont)
      }
    }
  }

  private var statusFont: Font {
    layout == .standard ? .body : .caption
  }

  private func quarterLabel(_ quarter: Int) -> some View {
    Text("Q\(quarter)")
      .accessibilityLabel(Text("Quarter \(quarter)"))
  }

  private func schedule(_ date: Date, day: String) -> some View {
    VStack(spacing: 0) {
      Text(date, format: .dateTime.hour().minute())
        .font(statusFont)
      Text(day)
        .font(layout == .standard ? .caption : .caption2)
    }
    .multilineTextAlignment(.center)
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
