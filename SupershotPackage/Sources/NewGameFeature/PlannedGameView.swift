import AlarmClient
import AppUI
import ComposableArchitecture
import Database
import FeatureFlagsClient
import GameAnalysis
import GameCore
import PermissionsFeature
import SharedModels
import SubscriptionClient
import SwiftUI
import UI

package struct PlannedGameView: View {
  @Dependency(\.featureFlags) private var featureFlags
  @Environment(\.scenePhase) private var scenePhase
  @Bindable package var store: StoreOf<PlannedGameFeature>
  package var proAccess: SubscriptionEntitlement

  package var body: some View {
    Group {
      if let snapshot = store.snapshot {
        List {
          PlannedTeamsSection(
            teamA: snapshot.teamA,
            teamB: snapshot.teamB,
            colorA: snapshot.game.teamABibColor,
            colorB: snapshot.game.teamBBibColor
          )
          PlannedDetailsSection(game: snapshot.game, teamA: snapshot.teamA, teamB: snapshot.teamB)
          PlannedTimingSection(periods: snapshot.periods, breakStartPolicy: snapshot.game.breakStartPolicy)
          PlannedLocationSection(location: snapshot.game.location)
          Section("Alerts") {
            if proAccess != .unknown, !featureFlags.isEnabled(.timerAlerts, proAccess) {
              Text("Timer alerts require Supershot Pro.")
                .foregroundStyle(.secondary)
            } else if proAccess == .unknown {
              Text("Checking availability…")
                .foregroundStyle(.secondary)
            } else {
              LabeledContent("Timer alerts") {
                Text(store.alarms.authorization == .authorized ? "Enabled" : "Not enabled")
              }
            }
          }
        }
      } else if store.isLoading {
        ProgressView("Loading game…")
      } else {
        ContentUnavailableView(
          "Game unavailable",
          systemImage: "exclamationmark.triangle",
          description: Text("This game could not be opened. It may have been deleted.")
        )
      }
    }
    .navigationTitle("Game")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Edit") { store.send(.editButtonTapped) }
          .disabled(store.isLoading || store.snapshot == nil)
          .accessibilityIdentifier("plannedGame.edit")
      }
    }
    .safeAreaBar(edge: .bottom) {
      VStack(spacing: 12) {
        if let error = store.errorMessage {
          Text(error)
            .font(.callout)
            .foregroundStyle(.secondary)
          Button("Try again") { store.send(.retryButtonTapped) }
            .disabled(store.isLoading)
        }
        if store.snapshot != nil {
          Button {
            store.send(.startGameButtonTapped)
          } label: {
            HStack {
              if store.isLoading {
                ProgressView()
              }
              Text("Start game")
            }
            .frame(maxWidth: .infinity)
            .padding(8)
          }
          .buttonStyle(.glassProminent)
          .disabled(store.isLoading || store.hasPreparedScoring)
          .accessibilityIdentifier("plannedGame.start")
        }
      }
      .padding()
      #if os(macOS)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
      #endif
    }
    .task {
      store.send(.refresh)
      store.send(.alarms(.refresh(proAccess)))
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        store.send(.refresh)
        store.send(.alarms(.refresh(proAccess)))
      }
    }
    .onChange(of: proAccess) { _, access in store.send(.alarms(.refresh(access))) }
    .sheet(item: $store.scope(state: \.editor, action: \.editor)) { editorStore in
      NavigationStack {
        NewGameView(store: editorStore, proAccess: proAccess, isEditingExistingGame: true)
      }
      .interactiveDismissDisabled(editorStore.isSaving)
    }
  }

  package init(store: StoreOf<PlannedGameFeature>, proAccess: SubscriptionEntitlement) {
    self.store = store
    self.proAccess = proAccess
  }
}

private struct PlannedTeamsSection: View {
  var teamA: Team
  var teamB: Team
  var colorA: Color
  var colorB: Color

  var body: some View {
    Section("Teams") {
      PlannedTeamRow(team: teamA, color: colorA)
      PlannedTeamRow(team: teamB, color: colorB)
    }
  }
}

private struct PlannedTeamRow: View {
  var team: Team
  var color: Color

  var body: some View {
    HStack(spacing: 12) {
      AvatarView(team.name, logoData: team.logoData)
        .backgroundStyle(color)
        .controlSize(.small)
        .accessibilityHidden(true)
      Text(team.name)
        .font(.headline)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct PlannedDetailsSection: View {
  var game: Game
  var teamA: Team
  var teamB: Team

  var body: some View {
    Section("Game details") {
      if let date = game.scheduledAt {
        LabeledContent("Scheduled") {
          Text(date, format: .dateTime.day().month().year().hour().minute())
            .multilineTextAlignment(.trailing)
        }
      } else {
        LabeledContent("Status", value: "Draft")
      }
      if let court = game.court, !court.isEmpty {
        LabeledContent("Court", value: court)
      }
      if let division = game.division, !division.isEmpty {
        LabeledContent("Division", value: division)
      }
      LabeledContent("First centre pass") {
        if game.centrePassTeamID == teamA.id {
          Text(teamA.name)
        } else if game.centrePassTeamID == teamB.id {
          Text(teamB.name)
        } else {
          Text("Not selected")
        }
      }
    }
  }
}

private struct PlannedTimingSection: View {
  var periods: [GamePeriod]
  var breakStartPolicy: BreakStartPolicy

  var body: some View {
    Section("Timing") {
      ForEach(periods) { period in
        LabeledContent("Quarter \(period.position + 1)") {
          Text(Duration.seconds(period.durationSeconds), format: .time(pattern: .minuteSecond))
        }
        if let seconds = period.breakAfterDurationSeconds {
          LabeledContent("Break after quarter \(period.position + 1)") {
            Text(Duration.seconds(seconds), format: .time(pattern: .minuteSecond))
          }
        }
      }
      LabeledContent("Breaks start") {
        Text(breakStartPolicy == .automatic ? "Automatically" : "Manually")
      }
    }
  }
}

private struct PlannedLocationSection: View {
  var location: GameLocation?

  var body: some View {
    Section("Location") {
      if let location {
        if let name = location.pointOfInterestName {
          Text(name)
        }
        GameLocationMap(location: location)
          .id(location)
      } else {
        Text("No location set")
          .foregroundStyle(.secondary)
      }
    }
  }
}
