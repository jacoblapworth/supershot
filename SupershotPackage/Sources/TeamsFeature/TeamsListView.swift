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

package struct TeamsListView: View {
  package let proAccess: SubscriptionEntitlement
  @Bindable package var store: StoreOf<TeamsFeature>
  package var isPresentingPaywall = false
  @Fetch(TeamsRequest(), animation: .default)
  private var teamsResponse = TeamsRequest.Value()

  package var body: some View {
    NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
      teamsList
    } destination: { pathStore in
      switch pathStore.case {
      case let .gameDetail(gameDetailStore):
        GameDetailView(
          store: gameDetailStore,
          showsProPromotion: proAccess == .free,
          proPromotionTapped: { store.send(.proPromotionTapped) }
        )
      case let .scoring(scoringStore):
        ScoringView(store: scoringStore, proAccess: proAccess, isPresentingPaywall: isPresentingPaywall)
        #if os(iOS)
          .toolbarVisibility(.hidden, for: .tabBar)
        #endif
      case let .teamDetail(teamDetailStore):
        TeamDetailView(
          store: teamDetailStore,
          isResumingGame: store.pendingGameResume != nil
        )
      }
    }
    .sheet(item: $store.scope(state: \.newGame, action: \.newGame)) { setupStore in
      NavigationStack {
        NewGameView(store: setupStore, proAccess: proAccess)
      }
      .interactiveDismissDisabled(setupStore.isSaving)
    }
    .alert($store.scope(state: \.destination?.alert, action: \.destination.alert))
    .sheet(item: $store.scope(state: \.destination?.teamEditor, action: \.destination.teamEditor)) {
      editorStore in
      TeamsEditorView(store: editorStore)
    }
  }

  private var teamsList: some View {
    let filteredTeams = store.state.filteredTeams(in: teamsResponse.teams)
    return List {
      if teamsResponse.teams.isEmpty {
        ContentUnavailableView(
          label: {
            Label("No teams yet", systemImage: "person.2")
          },
          description: {
            Text("Create a team to use in your next game.")
          },
          actions: {
            Button("New team") {
              store.send(.newTeamButtonTapped)
            }
            .buttonStyle(.borderedProminent)
            .fontWeight(.medium)
            .controlSize(.large)
          }
        )
        .listRowBackground(Color.clear)
      } else if filteredTeams.isEmpty {
        ContentUnavailableView.search(text: store.searchText.trimmingCharacters(in: .whitespacesAndNewlines))
          .listRowBackground(Color.clear)
      } else {
        ForEach(filteredTeams) { team in
          Button {
            store.send(.teamRowTapped(team))
          } label: {
            TeamRow(team: team)
          }
          .buttonStyle(.plain)
          .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) {
              store.send(.deleteTeamButtonTapped(team.id))
            }
          }
          .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", systemImage: "trash", role: .destructive) {
              store.send(.deleteTeamButtonTapped(team.id))
            }
          }
        }
      }
    }
    .navigationTitle("Teams")
    .searchable(text: $store.searchText, prompt: "Search teams")
    .searchPresentationToolbarBehavior(.automatic)
    .searchToolbarBehavior(.automatic)
    .tabViewSearchActivation(.searchTabSelection)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          store.send(.newTeamButtonTapped)
        } label: {
          Label("New team", systemImage: "plus")
        }
      }
    }
  }

  package init(
    proAccess: SubscriptionEntitlement,
    store: StoreOf<TeamsFeature>,
    isPresentingPaywall: Bool = false
  ) {
    self.proAccess = proAccess
    self.store = store
    self.isPresentingPaywall = isPresentingPaywall
  }
}

private struct TeamsEditorView: View {
  @Bindable var store: StoreOf<TeamsEditorFeature>

  var body: some View {
    NavigationStack {
      TeamEditorView(store: store.scope(state: \.editor, action: \.editor))
    }
    .alert($store.scope(state: \.alert, action: \.alert))
  }
}

private struct TeamRow: View {
  var team: TeamListItem

  var body: some View {
    HStack(spacing: 14) {
      Circle()
        .fill(team.color)
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)

      Text(team.name)
        .font(.headline)
        .foregroundStyle(.primary)

      Spacer(minLength: 12)

      Text(team.gameCount == 1 ? "1 game" : "\(team.gameCount) games")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

#Preview("Teams") {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.defaultDatabase.seedDebugExamplesIfNeeded()
  }
  TeamsListView(
    proAccess: .free,
    store: Store(initialState: TeamsFeature.State()) {
      TeamsFeature()
    }
  )
}
