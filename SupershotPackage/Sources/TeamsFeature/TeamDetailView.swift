import ComposableArchitecture
import Database
import Dependencies
import GameAnalysis
import GameCore
import GameDetailFeature
import GameServices
import NewGameFeature
import PaywallFeature
import PreviewSupport
import SQLiteData
import ScoringFeature
import SharedModels
import Styleguide
import SubscriptionClient
import SwiftUI
import TeamEditingFeature
import WidgetSupport

package struct TeamDetailView: View {
  @Fetch private var response: TeamDetailRequest.Value
  @Bindable package var store: StoreOf<TeamDetailFeature>
  package var isResumingGame: Bool

  package init(
    store: StoreOf<TeamDetailFeature>,
    isResumingGame: Bool
  ) {
    self.store = store
    self.isResumingGame = isResumingGame
    _response = Fetch(
      wrappedValue: TeamDetailRequest.Value(),
      TeamDetailRequest(teamID: store.teamID)
    )
  }

  package var body: some View {
    Group {
      if let team = response.team {
        teamContent(team)
      } else if $response.isLoading {
        TeamDetailLoadingView()
      } else {
        ContentUnavailableView(
          "Team unavailable",
          systemImage: "exclamationmark.triangle",
          description: Text("This team could not be loaded.")
        )
      }
    }
    .navigationTitle(response.team?.name ?? "Team")
    .toolbar {
      if let team = response.team {
        ToolbarItem(placement: .primaryAction) {
          Menu {
            Button("Edit", systemImage: "pencil") {
              store.send(.editButtonTapped(team))
            }
            Button("Delete team", systemImage: "trash", role: .destructive) {
              store.send(.deleteButtonTapped)
            }
          } label: {
            Label("Team actions", systemImage: "ellipsis")
          }
        }
      }
    }
    .sheet(item: $store.scope(state: \.editor, action: \.editor)) { editorStore in
      NavigationStack {
        TeamEditorView(store: editorStore)
      }
    }
  }

  private func teamContent(_ team: Team) -> some View {
    List {
      TeamStatisticsSection(statistics: response.statistics)
      Section("Games") {
        Button("New game", systemImage: "plus") {
          store.send(.newGameButtonTapped(team))
        }
        .disabled(isResumingGame)

        if response.games.isEmpty {
          ContentUnavailableView(
            "No games yet",
            systemImage: "sportscourt",
            description: Text("This team has no game history.")
          )
          .listRowBackground(Color.clear)
        } else {
          ForEach(response.games) { game in
            Button {
              store.send(.gameRowTapped(game))
            } label: {
              GameRow(game: game)
            }
            .listRowInsets(.all, 0)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .buttonStyle(.plain)
            .disabled(isResumingGame)
          }
        }
      }
    }
  }
}

private struct TeamStatisticsSection: View {
  let statistics: TeamStatistics

  var body: some View {
    Section {
      LabeledContent("Played", value: statistics.gamesPlayed.formatted())
      LabeledContent("Wins", value: statistics.wins.formatted())
      LabeledContent("Losses", value: statistics.losses.formatted())
      LabeledContent("Draws", value: statistics.draws.formatted())
      LabeledContent("Points scored", value: statistics.pointsScored.formatted())
      LabeledContent("Points against", value: statistics.pointsAgainst.formatted())
      LabeledContent("Points difference", value: statistics.pointsDifference.formatted())
      LabeledContent("Win percentage") {
        if let winRate = statistics.winRate {
          Text(winRate, format: .percent.precision(.fractionLength(0)))
        } else {
          Text("—")
            .accessibilityLabel("Unavailable")
        }
      }
    } header: {
      Text("Statistics")
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        Text("Completed games · All time")
        if statistics.gamesPlayed == 0 {
          Text("No completed games yet")
        }
      }
    }
    .monospacedDigit()
  }
}

private struct TeamDetailLoadingView: View {
  var body: some View {
    ProgressView("Loading team…")
  }
}

#Preview("Team detail") {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.defaultDatabase.seedDebugExamplesIfNeeded()
  }
  NavigationStack {
    TeamDetailView(
      store: Store(
        initialState: TeamDetailFeature.State(teamID: UUID(1))
      ) {
        TeamDetailFeature()
      },
      isResumingGame: false
    )
  }
}

#Preview("Empty team") {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.defaultDatabase.write { db in
      try Team.insert {
        Team(id: UUID(50), name: "Falcons", colorHex: "#34C759")
      }
      .execute(db)
    }
  }
  NavigationStack {
    TeamDetailView(
      store: Store(
        initialState: TeamDetailFeature.State(teamID: UUID(50))
      ) {
        TeamDetailFeature()
      },
      isResumingGame: false
    )
  }
}

#Preview("Unavailable team") {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
  }
  NavigationStack {
    TeamDetailView(
      store: Store(
        initialState: TeamDetailFeature.State(teamID: UUID(99))
      ) {
        TeamDetailFeature()
      },
      isResumingGame: false
    )
  }
}

#Preview("Loading team") {
  NavigationStack {
    TeamDetailLoadingView()
      .navigationTitle("Team")
  }
}
