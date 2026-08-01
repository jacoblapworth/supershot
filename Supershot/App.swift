import ComposableArchitecture
import Dependencies
import SQLiteData
import SwiftUI

struct AppView: View {
  @Fetch(GamesRequest(), animation: .default)
  private var response = GamesRequest.Value()
  @Bindable var store: StoreOf<AppFeature>

  var body: some View {
    NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
      GamesHomeView(
        games: response.games,
        loadingGameID: store.loadingGameID,
        gameTapped: { store.send(.gameRowTapped($0)) },
        newGameTapped: { store.send(.newGameButtonTapped) }
      )
    } destination: { pathStore in
      switch pathStore.case {
      case .gameDetail(let gameDetailStore):
        GameDetailView(store: gameDetailStore)
      case .scoring(let scoringStore):
        ScoringView(store: scoringStore)
      case .setup(let setupStore):
        SetupView(store: setupStore)
      }
    }
    .alert($store.scope(state: \.alert, action: \.alert))
  }
}

private struct GamesHomeView: View {
  var games: [GameListItem]
  var loadingGameID: Game.ID?
  var gameTapped: (GameListItem) -> Void
  var newGameTapped: () -> Void

  var body: some View {
    List {
      if games.isEmpty {
        ContentUnavailableView {
          Label("No games yet", systemImage: "sportscourt")
        } description: {
          Text("Start a game to keep score and build your history.")
        } actions: {
          Button("Start game", action: newGameTapped)
            .buttonStyle(.borderedProminent)
        }
        .listRowBackground(Color.clear)
      } else {
        ForEach(games) { game in
          Button {
            gameTapped(game)
          } label: {
            GameRow(
              game: game,
              isLoading: loadingGameID == game.id
            )
          }
          .buttonStyle(.plain)
          .disabled(loadingGameID != nil)
        }
      }
    }
    .navigationTitle("Games")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(action: newGameTapped) {
          Label("New game", systemImage: "plus")
        }
        .disabled(loadingGameID != nil)
      }
    }
  }
}

private struct GameRow: View {
  var game: GameListItem
  var isLoading: Bool

  var body: some View {
    VStack(spacing: 14) {
      HStack(spacing: 8) {
        Text(game.startedAt.formatted(date: .abbreviated, time: .shortened))
          .foregroundStyle(.secondary)

        Spacer(minLength: 8)

        if isLoading {
          ProgressView()
            .controlSize(.small)
        } else {
          Label(
            game.isCompleted ? "Final" : "In progress",
            systemImage: game.isCompleted ? "checkmark.circle.fill" : "clock.fill"
          )
          .foregroundStyle(game.isCompleted ? Color.secondary : Color.accentColor)
        }
      }
      .font(.caption.weight(.semibold))

      HStack(alignment: .center, spacing: 12) {
        TeamScore(
          alignment: .leading,
          colorHex: game.teamAColorHex,
          name: game.teamAName,
          score: game.teamAScore
        )

        Text("–")
          .font(.title2.bold())
          .foregroundStyle(.secondary)

        TeamScore(
          alignment: .trailing,
          colorHex: game.teamBColorHex,
          name: game.teamBName,
          score: game.teamBScore
        )
      }

      Text(game.timingSummary)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 8)
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }

  private var accessibilityText: String {
    let date = game.startedAt.formatted(date: .abbreviated, time: .shortened)
    let status = game.isCompleted ? "Final" : "In progress"
    return "\(date), \(game.teamAName) \(game.teamAScore), "
      + "\(game.teamBName) \(game.teamBScore), \(status), \(game.timingSummary)"
  }
}

private struct TeamScore: View {
  var alignment: HorizontalAlignment
  var colorHex: String
  var name: String
  var score: Int

  var body: some View {
    VStack(alignment: alignment, spacing: 4) {
      Circle()
        .fill(Color(teamHex: colorHex))
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)

      Text(name)
        .font(.headline)
        .lineLimit(3)
        .multilineTextAlignment(alignment == .leading ? .leading : .trailing)

      Text("\(score)")
        .font(.system(.title, design: .rounded, weight: .bold))
        .monospacedDigit()
    }
    .frame(
      maxWidth: .infinity,
      alignment: alignment == .leading ? .leading : .trailing
    )
  }
}

#Preview("Games") {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.defaultDatabase.seedPreviewGames()
  }
  AppView(
    store: Store(initialState: AppFeature.State()) {
      AppFeature()
    }
  )
}
