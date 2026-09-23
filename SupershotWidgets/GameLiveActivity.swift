import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct GameLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: GameActivityAttributes.self) { context in
      ActivityGameView(context: context)
        .activityBackgroundTint(.black.opacity(0.86))
        .activitySystemActionForegroundColor(.white)
        .widgetURL(context.attributes.gameURL)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          teamScore(
            color: context.attributes.teamAColor,
            centrePassDirection: .leading,
            isCentrePassTeam: context.state.centrePassTeamID == context.attributes.teamAID,
            name: context.attributes.teamAName,
            score: context.state.teamAScore
          )
        }
        DynamicIslandExpandedRegion(.trailing) {
          teamScore(
            color: context.attributes.teamBColor,
            centrePassDirection: .trailing,
            isCentrePassTeam: context.state.centrePassTeamID == context.attributes.teamBID,
            name: context.attributes.teamBName,
            score: context.state.teamBScore
          )
        }
        DynamicIslandExpandedRegion(.center) {
          phaseLabel(context.state)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack(spacing: 14) {
            GoalButton(context: context, isTeamA: true)
            TimerText(state: context.state, isStale: context.isStale)
              .font(.title2.bold())
              .frame(maxWidth: .infinity, alignment: .leading)
            GoalButton(context: context, isTeamA: false)
          }
        }
      } compactLeading: {
        Text(context.state.isInBreak ? "B" : "Q\(context.state.period)")
          .font(.caption.bold())
          .foregroundStyle(.black)
          .padding(4)
          .background(.white, in: .capsule)
      } compactTrailing: {
        TimerText(state: context.state, isStale: context.isStale)
          .font(.caption.monospacedDigit())
      } minimal: {
        TimerText(state: context.state, isStale: context.isStale)
          .font(.caption2.monospacedDigit())
      }
      
      .widgetURL(context.attributes.gameURL)
      .keylineTint(.orange)
    }
    .supplementalActivityFamilies([.small, .medium])
  }

  private func phaseLabel(
    _ state: GameActivityAttributes.ContentState
  ) -> Text {
    state.isInBreak ? Text("Break") : Text("Quarter \(state.period)")
  }

  private func teamScore(
    color: Color,
    centrePassDirection: Edge,
    isCentrePassTeam: Bool,
    name: String,
    score: Int
  ) -> some View {
    VStack(spacing: 2) {
      HStack(spacing: 3) {
        if isCentrePassTeam, centrePassDirection == .trailing {
          CentrePassIndicator(direction: centrePassDirection)
        }
        Text(name)
          .lineLimit(1)
        if isCentrePassTeam, centrePassDirection == .leading {
          CentrePassIndicator(direction: centrePassDirection)
        }
      }
      .font(.caption2.weight(.semibold))
      Text("\(score)")
        .font(.title.bold())
        .monospacedDigit()
        .foregroundStyle(color)
    }
    .frame(maxWidth: 92)
  }
}



private struct ActivityGameView: View {
  let context: ActivityViewContext<GameActivityAttributes>
  @Environment(\.activityFamily) private var activityFamily

  var body: some View {
    Group {
      switch activityFamily {
      case .small:
        SmallActivityGameView(context: context)
      case .medium:
        LockScreenGameView(context: context)
      @unknown default:
        fatalError("Widget only supports small and medium activity families")
      }
    }
    .padding(activityFamily == .small ? 8 : 16)
  }
}

private struct SmallActivityGameView: View {
  let context: ActivityViewContext<GameActivityAttributes>

  var body: some View {
    VStack(spacing: 6) {
      HStack(spacing: 8) {
        team(
          color: context.attributes.teamAColor,
          centrePassDirection: .leading,
          isCentrePassTeam: context.state.centrePassTeamID == context.attributes.teamAID,
          name: context.attributes.teamAName,
          score: context.state.teamAScore
        )
        team(
          color: context.attributes.teamBColor,
          centrePassDirection: .trailing,
          isCentrePassTeam: context.state.centrePassTeamID == context.attributes.teamBID,
          name: context.attributes.teamBName,
          score: context.state.teamBScore
        )
      }

      HStack(spacing: 6) {
        Text(context.state.isInBreak ? "Break" : "Q\(context.state.period)")
          .foregroundStyle(.secondary)
        TimerText(state: context.state, isStale: context.isStale)
      }
      .font(.caption.weight(.semibold))
    }
    .foregroundStyle(.white)
  }

  private func team(
    color: Color,
    centrePassDirection: Edge,
    isCentrePassTeam: Bool,
    name: String,
    score: Int
  ) -> some View {
    VStack(spacing: 1) {
      HStack(spacing: 2) {
        if isCentrePassTeam, centrePassDirection == .trailing {
          CentrePassIndicator(direction: centrePassDirection)
        }
        Text(name)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        if isCentrePassTeam, centrePassDirection == .leading {
          CentrePassIndicator(direction: centrePassDirection)
        }
      }
      .font(.caption2.weight(.semibold))

      Text("\(score)")
        .font(.title2.bold())
        .monospacedDigit()
        .foregroundStyle(color)
    }
    .frame(maxWidth: .infinity)
  }
}

private struct LockScreenGameView: View {
  let context: ActivityViewContext<GameActivityAttributes>

  var body: some View {
    VStack(spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Score(
          color: context.attributes.teamAColor,
          centrePassDirection: .leading,
          hasCentrePass: context.state.centrePassTeamID == context.attributes.teamAID,
          name: context.attributes.teamAName,
          score: context.state.teamAScore,
          alignment: .leading
        )
        Score(
          color: context.attributes.teamBColor,
          centrePassDirection: .trailing,
          hasCentrePass: context.state.centrePassTeamID == context.attributes.teamBID,
          name: context.attributes.teamBName,
          score: context.state.teamBScore,
          alignment: .trailing
        )
      }
      if context.state.isInBreak {
        HStack {
          VStack(alignment: .center, spacing: 0) {
            Text(context.state.isInBreak ? "Break" : "Quarter \(context.state.period)")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            TimerText(state: context.state, isStale: context.isStale)
              .font(.title.bold())
          }
          Spacer()
          TimerControl(attributes: context.attributes, isStale: context.isStale, state: context.state)
        }
      } else {
        GoalControls(context: context)
      }
    }
    .foregroundStyle(.white)
  }
}

private struct Score: View {
  var color: Color
  var centrePassDirection: Edge
  var hasCentrePass: Bool
  var name: String
  var score: Int
  var alignment: HorizontalAlignment
  
  var body: some View {
    VStack(alignment: alignment, spacing: 0) {
      HStack(spacing: 4) {
        if hasCentrePass, centrePassDirection == .trailing {
          CentrePassIndicator(direction: centrePassDirection)
        }
        Text(name)
          .lineLimit(2)
          .truncationMode(.middle)
          .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        if hasCentrePass, centrePassDirection == .leading {
          CentrePassIndicator(direction: centrePassDirection)
        }
      }
      .font(.subheadline)
      Text("\(score)")
        .font(.largeTitle)
        .fontWeight(.bold)
      //        .fontWidth(.condensed)
      //        .font(.system(.largeTitle, design: .monospaced, weight: .bold))
      //        .monospacedDigit()
        .foregroundStyle(color)
    }
    .frame(
      maxWidth: .infinity,
      alignment: alignment == .leading ? .leading : .trailing
    )
  }
}

private struct CentrePassIndicator: View {
  var direction: Edge

  var body: some View {
    Image(
      systemName: direction == .leading
        ? "arrow.left.circle.fill"
        : "arrow.right.circle.fill"
    )
    .accessibilityLabel("Current centre pass")
  }
}

private struct TimerText: View {
  var state: GameActivityAttributes.ContentState
  var isStale: Bool

  var body: some View {
    if isStale || state.isComplete {
      Text(state.isInBreak ? "Break ended" : "Quarter ended")
        .lineLimit(1)
    } else if let timerEndsAt = state.timerEndsAt {
      Text(
        timerInterval: timerEndsAt.addingTimeInterval(
          -TimeInterval(state.remainingSeconds)
        )...timerEndsAt,
        countsDown: true,
        showsHours: false
      )
      .multilineTextAlignment(.center)
      .contentTransition(.numericText(countsDown: true))
      .monospacedDigit()
    } else {
      Text(state.remainingSeconds.formattedClock)
        .monospacedDigit()
        .contentTransition(.numericText(countsDown: true))
    }
  }
}



private struct GoalButton: View {
  let context: ActivityViewContext<GameActivityAttributes>
  var isTeamA: Bool

  var body: some View {
    Button(intent: ScoreGoalIntent(
      gameID: context.attributes.gameID,
      teamID: isTeamA ? context.attributes.teamAID : context.attributes.teamBID,
      expectedPhaseIndex: context.state.phaseIndex
    )) {
      Label("Goal", systemImage: "plus")
        .font(.title3.bold())
        .labelStyle(.iconOnly)
        .frame(minWidth: 80, minHeight: 32)
    }
    .buttonStyle(.glassProminent)
    .tint(isTeamA ? context.attributes.teamAColor : context.attributes.teamBColor)
    .accessibilityLabel("Goal for \(isTeamA ? context.attributes.teamAName : context.attributes.teamBName)")
    .disabled(
      context.isStale
        || context.state.isComplete
        || context.state.isInBreak
        || context.state.timerEndsAt == nil
        || context.state.isAwaitingCentrePassConfirmation
    )
  }
}

private struct GoalControls: View {
  let context: ActivityViewContext<GameActivityAttributes>
  var body: some View {
    HStack {
      GoalButton(context: context, isTeamA: true)
      Spacer()
      VStack(alignment: .center, spacing: 0) {
        Text(context.state.isInBreak ? "Break" : "Quarter \(context.state.period)")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        TimerText(state: context.state, isStale: context.isStale)
          .font(.title.bold())
      }
      Spacer()
      GoalButton(context: context, isTeamA: false)
    }
  }
}

private struct TimerControl: View {
  var attributes: GameActivityAttributes
  var isStale: Bool
  var state: GameActivityAttributes.ContentState

  var body: some View {
    if !isStale, !state.isComplete {
      if state.timerEndsAt != nil {
        Button(
          intent: PauseGameTimerIntent(
            gameID: attributes.gameID,
            expectedPhaseIndex: state.phaseIndex
          )
        ) {
          Image(systemName: "pause.fill")
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .accessibilityLabel("Pause timer")
      } else {
        Button(
          intent: ResumeGameTimerIntent(
            gameID: attributes.gameID,
            expectedPhaseIndex: state.phaseIndex
          )
        ) {
          Image(systemName: "play.fill")
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .accessibilityLabel("Resume timer")
      }
    }
  }
}

private extension GameActivityAttributes {
  var gameURL: URL? {
    URL(string: "supershot://game/\(gameID.uuidString)")
  }

  static let preview = Self(
    gameID: UUID(),
    teamAID: UUID(),
    teamAColorHex: "#007AFF",
    teamAName: "North London Ravens",
    teamBID: UUID(),
    teamBColorHex: "#FF3B30",
    teamBName: "Westminster Swifts"
  )
}

private extension GameActivityAttributes.ContentState {
  var isInBreak: Bool { !phaseIndex.isMultiple(of: 2) }

  var period: Int { phaseIndex / 2 + 1 }

  var isComplete: Bool {
    elapsedSeconds >= currentDurationSeconds
  }

  var remainingSeconds: Int {
    max(currentDurationSeconds - elapsedSeconds, 0)
  }

  static let pausedPreview = Self(
    centrePassTeamID: GameActivityAttributes.preview.teamAID,
    currentDurationSeconds: 900,
    elapsedSeconds: 245,
    phaseIndex: 2,
    teamAScore: 18,
    teamBScore: 16,
    timerEndsAt: nil
  )

  static let runningPreview = Self(
    centrePassTeamID: GameActivityAttributes.preview.teamAID,
    currentDurationSeconds: 900,
    elapsedSeconds: 245,
    phaseIndex: 2,
    teamAScore: 18,
    teamBScore: 16,
    timerEndsAt: Date.now.addingTimeInterval(655)
  )

  static let endedPreview = Self(
    centrePassTeamID: GameActivityAttributes.preview.teamAID,
    currentDurationSeconds: 900,
    elapsedSeconds: 900,
    phaseIndex: 2,
    teamAScore: 18,
    teamBScore: 16,
    timerEndsAt: nil
  )
}

private extension Int {
  var formattedClock: String {
    "\(self / 60):\(String(format: "%02d", self % 60))"
  }
}

#Preview("Running", as: .content, using: GameActivityAttributes.preview) {
  GameLiveActivity()
} contentStates: {
  GameActivityAttributes.ContentState.runningPreview
  GameActivityAttributes.ContentState.pausedPreview
}

#Preview("Paused", as: .content, using: GameActivityAttributes.preview) {
  GameLiveActivity()
} contentStates: {
  GameActivityAttributes.ContentState.pausedPreview
}

#Preview("Ended", as: .content, using: GameActivityAttributes.preview) {
  GameLiveActivity()
} contentStates: {
  GameActivityAttributes.ContentState.endedPreview
}

#Preview(
  "Dynamic Island Expanded",
  as: .dynamicIsland(.expanded),
  using: GameActivityAttributes.preview
) {
  GameLiveActivity()
} contentStates: {
  GameActivityAttributes.ContentState.runningPreview
}

#Preview(
  "Dynamic Island Compact",
  as: .dynamicIsland(.compact),
  using: GameActivityAttributes.preview
) {
  GameLiveActivity()
} contentStates: {
  GameActivityAttributes.ContentState.runningPreview
}

#Preview(
  "Dynamic Island Minimal",
  as: .dynamicIsland(.minimal),
  using: GameActivityAttributes.preview
) {
  GameLiveActivity()
} contentStates: {
  GameActivityAttributes.ContentState.runningPreview
}
