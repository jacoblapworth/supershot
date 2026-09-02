import ComposableArchitecture
import Dependencies
import SQLiteData
import SwiftUI

struct TeamDetailView: View {
  @Fetch private var response: TeamDetailRequest.Value
  @Bindable var store: StoreOf<TeamDetailFeature>
  var deletingGameID: Game.ID?
  var loadingGameID: Game.ID?

  init(
    store: StoreOf<TeamDetailFeature>,
    deletingGameID: Game.ID?,
    loadingGameID: Game.ID?
  ) {
    self.store = store
    self.deletingGameID = deletingGameID
    self.loadingGameID = loadingGameID
    _response = Fetch(
      wrappedValue: TeamDetailRequest.Value(),
      TeamDetailRequest(teamID: store.teamID)
    )
  }

  var body: some View {
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
      Section {
        HStack(spacing: 16) {
          Circle()
            .fill(Color(teamHex: team.colorHex))
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 4) {
            Text(team.name)
              .font(.title2.bold())
            Text(response.games.count == 1 ? "1 game" : "\(response.games.count) games")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
      }

      Section("Games") {
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
            .buttonStyle(.plain)
            .disabled(loadingGameID != nil || deletingGameID != nil)
          }
        }
      }
    }
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
      deletingGameID: nil,
      loadingGameID: nil
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
      deletingGameID: nil,
      loadingGameID: nil
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
      deletingGameID: nil,
      loadingGameID: nil
    )
  }
}

#Preview("Loading team") {
  NavigationStack {
    TeamDetailLoadingView()
      .navigationTitle("Team")
  }
}
