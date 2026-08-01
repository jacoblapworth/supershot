import ComposableArchitecture
import Dependencies
import SQLiteData
import SwiftUI

struct GameDetailView: View {
  @Fetch private var response: GameDetailRequest.Value
  let store: StoreOf<GameDetailFeature>

  init(store: StoreOf<GameDetailFeature>) {
    self.store = store
    _response = Fetch(
      wrappedValue: GameDetailRequest.Value(),
      GameDetailRequest(gameID: store.gameID)
    )
  }

  var body: some View {
    Group {
      if let detail = response.detail {
        detailContent(detail)
      } else if $response.isLoading {
        ProgressView("Loading game…")
      } else {
        ContentUnavailableView(
          "Game unavailable",
          systemImage: "exclamationmark.triangle",
          description: Text("This game could not be loaded.")
        )
      }
    }
    .navigationTitle("Game")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func detailContent(_ detail: CompletedGameDetail) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        overview(detail)
        timeline(detail)
      }
      .padding()
    }
  }

  private func overview(_ detail: CompletedGameDetail) -> some View {
    VStack(spacing: 20) {
      Image(systemName: "flag.checkered")
        .font(.system(size: 40, weight: .semibold))
        .foregroundStyle(.secondary)

      Text(detail.resultTitle)
        .font(.largeTitle.bold())
        .multilineTextAlignment(.center)

      HStack(alignment: .top, spacing: 16) {
        GameDetailScore(
          alignment: .leading,
          name: detail.teamAName,
          score: detail.teamAScore
        )

        Text("–")
          .font(.title.bold())
          .foregroundStyle(.secondary)
          .padding(.top, 36)

        GameDetailScore(
          alignment: .trailing,
          name: detail.teamBName,
          score: detail.teamBScore
        )
      }

      Divider()

      VStack(alignment: .leading, spacing: 8) {
        LabeledContent("Started") {
          Text(detail.startedAt.formatted(date: .abbreviated, time: .shortened))
        }
        LabeledContent("Finished") {
          Text(detail.endedAt.formatted(date: .abbreviated, time: .shortened))
        }
      }
      .font(.subheadline)
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private func timeline(_ detail: CompletedGameDetail) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Goal timeline")
        .font(.title2.bold())

      if detail.goals.isEmpty {
        ContentUnavailableView(
          "No goals recorded",
          systemImage: "soccerball",
          description: Text("This game finished without a recorded goal.")
        )
        .frame(maxWidth: .infinity)
      } else {
        LazyVStack(spacing: 12) {
          ForEach(detail.goals) { goal in
            GoalTimelineRow(
              goal: goal,
              teamAName: detail.teamAName,
              teamBName: detail.teamBName
            )
          }
        }
      }
    }
  }
}

private struct GameDetailScore: View {
  var alignment: HorizontalAlignment
  var name: String
  var score: Int

  var body: some View {
    VStack(alignment: alignment, spacing: 8) {
      Text(name)
        .font(.headline)
        .lineLimit(3)
        .multilineTextAlignment(alignment == .leading ? .leading : .trailing)

      Text("\(score)")
        .font(.system(.largeTitle, design: .rounded, weight: .bold))
        .monospacedDigit()
    }
    .frame(
      maxWidth: .infinity,
      alignment: alignment == .leading ? .leading : .trailing
    )
  }
}

private struct GoalTimelineRow: View {
  var goal: GoalTimelineItem
  var teamAName: String
  var teamBName: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "soccerball")
        .font(.title3)
        .foregroundStyle(.tint)
        .frame(width: 28, height: 28)
        .background(.tint.opacity(0.12), in: Circle())

      VStack(alignment: .leading, spacing: 5) {
        Text(goal.scoringTeamName)
          .font(.headline)
          .lineLimit(2)

        Text("Quarter \(goal.period) · \(formattedTime(goal.clockSecondsRemaining)) remaining")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Text("\(teamAName) \(goal.teamAScore) – \(goal.teamBScore) \(teamBName)")
          .font(.subheadline.weight(.semibold))
          .lineLimit(2)

        Text("+\(goal.points) \(goal.points == 1 ? "point" : "points")")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .combine)
  }

  private func formattedTime(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let seconds = seconds % 60
    return "\(minutes):\(String(format: "%02d", seconds))"
  }
}

#Preview("Completed game") {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.defaultDatabase.seedPreviewGames()
  }
  NavigationStack {
    GameDetailView(
      store: Store(
        initialState: GameDetailFeature.State(gameID: UUID(10))
      ) {
        GameDetailFeature()
      }
    )
  }
}
