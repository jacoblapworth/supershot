import ComposableArchitecture
import Dependencies
import SQLiteData
import SwiftUI

struct TeamsHomeView: View {
  let proAccess: SubscriptionEntitlement
  @Bindable var store: StoreOf<TeamsFeature>
  @Fetch(TeamsRequest(), animation: .default)
  private var teamsResponse = TeamsRequest.Value()

  var body: some View {
    NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
      teamsList
    } destination: { pathStore in
      switch pathStore.case {
      case .gameDetail(let gameDetailStore):
        GameDetailView(
          store: gameDetailStore,
          showsProPromotion: proAccess == .free,
          proPromotionTapped: { store.send(.proPromotionTapped) }
        )
      case .scoring(let scoringStore):
        ScoringView(store: scoringStore)
#if os(iOS)
          .toolbarVisibility(.hidden, for: .tabBar)
#endif
      case .teamDetail(let teamDetailStore):
        TeamDetailView(
          store: teamDetailStore,
          isResumingGame: store.pendingGameResume != nil
        )
      }
    }
    .alert($store.scope(state: \.alert, action: \.alert))
    .sheet(item: $store.scope(state: \.teamEditor, action: \.teamEditor)) { editorStore in
      NavigationStack {
        TeamEditorView(store: editorStore)
      }
    }
  }

  private var teamsList: some View {
    List {
      if teamsResponse.teams.isEmpty {
        ContentUnavailableView(
          "No teams yet",
          systemImage: "person.2",
          description: Text("Create a team to use in your next game.")
        )
        .listRowBackground(Color.clear)
      } else {
        ForEach(teamsResponse.teams) { team in
          Button {
            store.send(.teamRowTapped(team))
          } label: {
            TeamRow(team: team)
          }
          .buttonStyle(.plain)
          .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", systemImage: "trash", role: .destructive) {
              store.send(.deleteTeamButtonTapped(team.id))
            }
          }
        }
      }
    }
    .navigationTitle("Teams")
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
  TeamsHomeView(
    proAccess: .free,
    store: Store(initialState: TeamsFeature.State()) {
      TeamsFeature()
    }
  )
}
