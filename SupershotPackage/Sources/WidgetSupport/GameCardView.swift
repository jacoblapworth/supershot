import SwiftUI

/// The list and Home Screen share team colours, identities, score hierarchy and status text.
public struct GameCardView: View {
  public var game: WidgetGame
  public var compact: Bool
  public var featured: Bool

  public init(game: WidgetGame, compact: Bool = false, featured: Bool = false) {
    self.game = game
    self.compact = compact
    self.featured = featured
  }

  public var body: some View {
    VStack(spacing: compact ? 4 : 8) {
      if featured {
        featuredTeams
      } else {
        HStack(spacing: 12) {
          team(name: game.teamAName, score: game.teamAScore,
               opponentScore: game.teamBScore, alignment: .leading)
          team(name: game.teamBName, score: game.teamBScore,
               opponentScore: game.teamAScore, alignment: .trailing)
        }
        HStack(spacing: 6) {
          Text(dateText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
          if !compact, let court = game.court { Text("Court \(court)") }
          Spacer(minLength: 0)
          status
        }
        .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
        .foregroundStyle(compact ? AnyShapeStyle(.primary.opacity(0.8)) : AnyShapeStyle(.thickMaterial))
      }
    }
    .padding(compact ? 8 : 16)
    .frame(maxWidth: .infinity, maxHeight: compact ? .infinity : nil)
    .background {
      LinearGradient(
        stops: [.init(color: Color(hex: game.teamAColorHex), location: 0.2),
                .init(color: Color(hex: game.teamBColorHex), location: 0.8)],
        startPoint: featured ? .top : .leading,
        endPoint: featured ? .bottom : .trailing
      )
    }
    .contentShape(.rect)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }

  private var featuredTeams: some View {
    VStack(spacing: 4) {
      featuredTeam(name: game.teamAName, score: game.teamAScore, opponent: game.teamBScore)
      Spacer(minLength: 0)
      VStack(spacing: 2) {
        status
        Text(dateText)
          .lineLimit(2)
          .minimumScaleFactor(0.8)
        if let court = game.court { Text("Court \(court)").lineLimit(1) }
      }
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.primary.opacity(0.8))
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      Spacer(minLength: 0)
      featuredTeam(name: game.teamBName, score: game.teamBScore, opponent: game.teamAScore)
    }
  }

  private func featuredTeam(name: String, score: Int, opponent: Int) -> some View {
    HStack(spacing: 6) {
      avatar(name).controlSize(.mini)
      Text(name).font(.subheadline.bold()).lineLimit(2).minimumScaleFactor(0.8)
      Spacer(minLength: 0)
      if !game.isPlanned { scoreText(score, opponent: opponent, size: 30) }
    }
  }

  private func team(
    name: String, score: Int, opponentScore: Int, alignment: HorizontalAlignment
  ) -> some View {
    VStack(alignment: alignment, spacing: 4) {
      if compact {
        HStack(spacing: 6) {
          if alignment == .leading { avatar(name).controlSize(.mini) }
          Text(name).font(.caption.bold()).lineLimit(2).minimumScaleFactor(0.8)
          if !game.isPlanned { scoreText(score, opponent: opponentScore, size: 32) }
          if alignment == .trailing { avatar(name).controlSize(.mini) }
        }
      } else {
        Text(name).font(.headline).lineLimit(1).truncationMode(.middle)
          .foregroundStyle(.thickMaterial)
        HStack(spacing: 16) {
          if alignment == .leading { avatar(name) }
          if !game.isPlanned { scoreText(score, opponent: opponentScore, size: 62) }
          if alignment == .trailing { avatar(name) }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
  }

  private func avatar(_ name: String) -> some View {
    AvatarView(name).backgroundStyle(.ultraThinMaterial).foregroundStyle(.ultraThickMaterial)
  }

  private func scoreText(_ score: Int, opponent: Int, size: CGFloat) -> some View {
    Text(score, format: .number)
      .font(.system(size: size, weight: .bold)).fontWidth(.compressed).monospacedDigit()
      .foregroundStyle(game.isCompleted && score < opponent ? .secondary : .primary)
      .lineLimit(1).minimumScaleFactor(0.6).layoutPriority(1)
  }

  private var status: some View {
    Label {
      if game.isPlanned { Text("Planned") }
      else if game.isCompleted { Text("Final") }
      else { Text("Q\(game.period)") }
    } icon: {
      Image(systemName: game.isPlanned ? "calendar" : game.isCompleted ? "checkmark.circle.fill" : "clock.fill")
    }
    .fixedSize()
  }

  private var dateText: String {
    if game.isPlanned {
      return game.scheduledAt?.formatted(date: .abbreviated, time: .shortened)
        ?? String(localized: "Unscheduled")
    }
    return game.startedAt?.formatted(date: .abbreviated, time: .shortened) ?? ""
  }

  private var accessibilityText: String {
    let court = game.court.map { String(localized: ", Court \($0)") } ?? ""
    if game.isPlanned {
      return String(localized: "\(game.teamAName) versus \(game.teamBName), Planned, \(dateText)\(court)")
    }
    let status = game.isCompleted ? String(localized: "Final") : String(localized: "Quarter \(game.period)")
    return String(localized: "\(game.teamAName) \(game.teamAScore), \(game.teamBName) \(game.teamBScore), \(status), \(dateText)\(court)")
  }
}
