import AppUI
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
import ScoringFeature
import SharedModels
import SQLiteData
import SubscriptionClient
import SwiftUI
import TeamEditingFeature
import UI

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
          Button("Edit", systemImage: "pencil") {
            store.send(.editButtonTapped(team))
          }
        }
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
        ToolbarItem(placement: newGameToolbarPlacement) {
          Button("New game", systemImage: "plus") {
            store.send(.newGameButtonTapped(team))
          }
          .disabled(isResumingGame)
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
      Section {
        HStack(spacing: 16) {
          AvatarView(team.name, logoData: team.logoData)
            .backgroundStyle(team.color)
            .controlSize(.large)
            .accessibilityHidden(true)
          Text(team.name).font(.title2.bold())
        }
      }
      TeamStatisticsSection(statistics: response.statistics)
      Section {
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
            #if os(iOS)
            .listRowSpacing(8)
            #endif
            .listRowInsets(.all, 0)
            .listRowSeparator(.hidden)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .buttonStyle(.plain)
            .disabled(isResumingGame)
          }
        }
      }
    }
    .scrollEdgeEffectStyle(.soft, for: .all)
  }

  private var newGameToolbarPlacement: ToolbarItemPlacement {
    #if os(iOS)
      .bottomBar
    #else
      .automatic
    #endif
  }
}

private struct TeamStatisticsSection: View {
  let statistics: TeamStatistics

  var body: some View {
    Group {
      Section {
        HStack {
          GroupBox("Won") {
            Text(statistics.wins.formatted())
          }
          GroupBox("Lost") {
            Text(statistics.losses.formatted())
          }
          GroupBox("Draw") {
            Text(statistics.draws.formatted())
          }
        }
      }
      .listRowInsets(.all, 0)
      .listRowBackground(Color.clear)

      Section {
        HStack {
          GroupBox("Scored") {
            Text(statistics.pointsScored, format: .number)
          }
          GroupBox("Against") {
            Text(statistics.pointsAgainst, format: .number)
          }
          GroupBox("Difference") {
            Text(
              statistics.pointsDifference,
              format: .number.sign(strategy: .always(includingZero: false))
            )
          }
        }
      } header: {
        Text("Points")
      }
    }
    .listRowInsets(.all, 0)
    .listRowBackground(Color.clear)
    .groupBoxStyle(.statGroupBoxStyle)
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
      store: Store(initialState: TeamDetailFeature.State(teamID: UUID(1))) {
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
      store: Store(initialState: TeamDetailFeature.State(teamID: UUID(50))) {
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
      store: Store(initialState: TeamDetailFeature.State(teamID: UUID(99))) {
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
