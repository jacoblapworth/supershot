import Charts
import SwiftUI

struct GoalProgressChartView: View {
  var detail: CompletedGameDetail
  @State private var breakdown = GoalProgressBreakdown.wholeGame
  @State private var selectedMoment: GoalProgressMoment?

  private var orderedPeriods: [GamePeriod] {
    detail.periods.sorted { $0.position < $1.position }
  }

  private var breakdownOptions: [GoalProgressBreakdown] {
    [.wholeGame] + orderedPeriods.map { .period($0.number) }
  }

  private var periodEndOffsets: [Int] {
    orderedPeriods.dropLast().reduce(into: []) { offsets, period in
      offsets.append((offsets.last ?? 0) + period.durationSeconds)
    }
  }

  private var goals: [GoalTimelineItem] {
    detail.goalTimeline.quarters
      .filter { breakdown.period == nil || $0.period == breakdown.period }
      .sorted(using: KeyPathComparator(\.period))
      .flatMap { quarter in
        quarter.goals.sorted { $0.clockSecondsRemaining > $1.clockSecondsRemaining }
      }
  }

  private var progress: GoalProgress {
    var points = [
      GoalProgressPoint(
        id: "start-teamA",
        elapsedSeconds: 0,
        score: 0,
        showsMarker: false,
        team: .teamA
      ),
      GoalProgressPoint(
        id: "start-teamB",
        elapsedSeconds: 0,
        score: 0,
        showsMarker: false,
        team: .teamB
      ),
    ]
    var moments: [GoalProgressMoment] = []
    var teamAScore = 0
    var teamBScore = 0

    for goal in goals {
      if breakdown == .wholeGame {
        teamAScore = goal.teamAScore
        teamBScore = goal.teamBScore
      } else {
        switch goal.scoringTeamSide {
        case .teamA:
          teamAScore += goal.points
        case .teamB:
          teamBScore += goal.points
        case .unknown:
          break
        }
      }

      guard let period = orderedPeriods.first(where: { $0.number == goal.period }) else {
        continue
      }
      let periodElapsedSeconds = max(period.durationSeconds - goal.clockSecondsRemaining, 0)
      let elapsedSeconds = breakdown == .wholeGame
        ? orderedPeriods
          .prefix { $0.position < period.position }
          .reduce(periodElapsedSeconds) { $0 + $1.durationSeconds }
        : periodElapsedSeconds
      moments.append(
        GoalProgressMoment(
          id: goal.id,
          elapsedSeconds: elapsedSeconds,
          period: goal.period,
          periodElapsedSeconds: periodElapsedSeconds,
          teamAScore: teamAScore,
          teamBScore: teamBScore
        )
      )
      points.append(
        GoalProgressPoint(
          id: "\(goal.id)-teamA",
          elapsedSeconds: elapsedSeconds,
          score: teamAScore,
          showsMarker: goal.scoringTeamSide == .teamA,
          team: .teamA
        )
      )
      points.append(
        GoalProgressPoint(
          id: "\(goal.id)-teamB",
          elapsedSeconds: elapsedSeconds,
          score: teamBScore,
          showsMarker: goal.scoringTeamSide == .teamB,
          team: .teamB
        )
      )
    }

    return GoalProgress(moments: moments, points: points)
  }

  private var displayedDuration: Int {
    if breakdown == .wholeGame {
      return max(orderedPeriods.reduce(0) { $0 + $1.durationSeconds }, 1)
    }
    return max(
      orderedPeriods.first { $0.number == breakdown.period }?.durationSeconds ?? 0,
      1
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Goal progression")
        .frame(maxWidth: .infinity, alignment: .center)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)

      Picker("Breakdown", selection: $breakdown) {
        ForEach(breakdownOptions) { breakdown in
          Text(breakdown.title).tag(breakdown)
        }
      }
      .pickerStyle(.segmented)
      .onChange(of: breakdown) { selectedMoment = nil }

      if progress.moments.isEmpty {
        ContentUnavailableView(
          "No goals recorded in \(breakdown.title)",
          systemImage: "chart.xyaxis.line",
          description: Text("Goal progression will appear here once goals are recorded.")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
      } else {
        Chart {
          ForEach(progress.points) { point in
            LineMark(
              x: .value("Playing time", point.elapsedSeconds),
              y: .value("Score", point.score),
              series: .value("Team", point.team.rawValue)
            )
            .foregroundStyle(color(for: point.team))
            .interpolationMethod(.stepEnd)

            if point.showsMarker {
              PointMark(
                x: .value("Playing time", point.elapsedSeconds),
                y: .value("Score", point.score)
              )
              .foregroundStyle(color(for: point.team))
              .symbolSize(24)
            }
          }

          if breakdown == .wholeGame {
            ForEach(periodEndOffsets, id: \.self) { periodEndOffset in
              RuleMark(
                x: .value("Break", periodEndOffset)
              )
              .foregroundStyle(.secondary.opacity(0.7))
              .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
              .annotation(position: .top) {
                Text("Break")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }

          if let selectedMoment {
            RuleMark(x: .value("Selected time", selectedMoment.elapsedSeconds))
              .foregroundStyle(.primary.opacity(0.5))
              .lineStyle(StrokeStyle(lineWidth: 1))
              .annotation(position: .top, alignment: .leading) {
                GoalProgressTooltip(
                  detail: detail,
                  moment: selectedMoment
                )
              }
          }
        }
        .chartXScale(domain: 0...displayedDuration)
//        .chartXAxisLabel("Playing time", alignment: .center)
//        .chartYAxisLabel("Score", alignment: .center)
        .chartXAxis {
          AxisMarks(values: .automatic(desiredCount: 5)) { value in
            AxisGridLine()
            AxisTick()
            AxisValueLabel {
              if let seconds = value.as(Int.self) {
                Text(formattedElapsedTime(seconds))
              }
            }
          }
        }
        .chartYAxis {
          AxisMarks(position: .leading) { _ in
            AxisGridLine()
            AxisTick()
            AxisValueLabel()
          }
        }
        .frame(height: 220)
        .chartOverlay { proxy in
          GeometryReader { geometry in
            Rectangle()
              .fill(.clear)
              .contentShape(Rectangle())
              .gesture(
                DragGesture(minimumDistance: 0)
                  .onChanged { value in
                    updateSelectedMoment(
                      at: value.location,
                      proxy: proxy,
                      geometry: geometry
                    )
                  }
                  .onEnded { _ in
                    selectedMoment = nil
                  }
              )
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          "\(breakdown.title) goal progression chart. \(detail.teamAName) has "
            + "\(progress.finalTeamAScore) points. "
            + "\(detail.teamBName) has \(progress.finalTeamBScore) points."
        )
      }
      
      GoalProgressLegend(detail: detail)
    
    }
  }

  private func color(for team: GoalProgressTeam) -> Color {
    switch team {
    case .teamA:
      Color(teamHex: detail.teamABibColorHex)
    case .teamB:
      Color(teamHex: detail.teamBBibColorHex)
    }
  }

  private func formattedElapsedTime(_ seconds: Int) -> String {
    let seconds = max(seconds, 0)
    return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
  }

  private func updateSelectedMoment(
    at location: CGPoint,
    proxy: ChartProxy,
    geometry: GeometryProxy
  ) {
    guard let plotFrame = proxy.plotFrame else {
      selectedMoment = nil
      return
    }
    let plotArea = geometry[plotFrame]
    guard plotArea.contains(location) else {
      selectedMoment = nil
      return
    }
    guard let elapsedSeconds = proxy.value(
      atX: location.x - plotArea.origin.x,
      as: Int.self
    ) else {
      selectedMoment = nil
      return
    }
    selectedMoment = progress.moments.min {
      abs($0.elapsedSeconds - elapsedSeconds) < abs($1.elapsedSeconds - elapsedSeconds)
    }
  }
}

private struct GoalProgressLegend: View {
  var detail: CompletedGameDetail

  var body: some View {
    HStack(spacing: 16) {
      label(detail.teamAName, colorHex: detail.teamABibColorHex)
      label(detail.teamBName, colorHex: detail.teamBBibColorHex)
    }
    .font(.caption.weight(.medium))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(detail.teamAName) is shown in its team colour. "
        + "\(detail.teamBName) is shown in its team colour."
    )
  }

  private func label(_ name: String, colorHex: String) -> some View {
    HStack(spacing: 5) {
      Circle()
        .fill(Color(teamHex: colorHex))
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
      Text(name)
        .lineLimit(1)
    }
  }
}

private enum GoalProgressTeam: String {
  case teamA
  case teamB
}

private enum GoalProgressBreakdown: Hashable, Identifiable {
  case wholeGame
  case period(Int)

  var id: Self { self }

  var period: Int? {
    guard case let .period(period) = self else { return nil }
    return period
  }

  var title: String {
    switch self {
    case .wholeGame:
      "Game"
    case let .period(period):
      "Q\(period)"
    }
  }
}

private struct GoalProgress {
  let moments: [GoalProgressMoment]
  let points: [GoalProgressPoint]

  var finalTeamAScore: Int {
    moments.last?.teamAScore ?? 0
  }

  var finalTeamBScore: Int {
    moments.last?.teamBScore ?? 0
  }
}

private struct GoalProgressMoment: Identifiable {
  let id: Goal.ID
  let elapsedSeconds: Int
  let period: Int
  let periodElapsedSeconds: Int
  let teamAScore: Int
  let teamBScore: Int
}

private struct GoalProgressPoint: Identifiable {
  let id: String
  let elapsedSeconds: Int
  let score: Int
  let showsMarker: Bool
  let team: GoalProgressTeam
}

private struct GoalProgressTooltip: View {
  var detail: CompletedGameDetail
  var moment: GoalProgressMoment

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Q\(moment.period) · \(formattedElapsedTime(moment.periodElapsedSeconds))")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text("\(detail.teamAName) \(moment.teamAScore) - \(moment.teamBScore) \(detail.teamBName)")
        .font(.caption.weight(.bold))
        .monospacedDigit()
    }
    .padding(8)
    .background(.background, in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(.quaternary)
    }
  }

  private func formattedElapsedTime(_ seconds: Int) -> String {
    let seconds = max(seconds, 0)
    return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
  }
}

#Preview("Goal progression") {
  GoalProgressChartView(detail: .previewCompleted)
    .padding()
}

#Preview("Empty goal progression") {
  GoalProgressChartView(detail: .previewNoGoals)
    .padding()
}
