import AppSettings
import ComposableArchitecture
import Database
import FixtureTeamResolution
import GameAnalysis
import GameCore
import GameServices
import LocationClient
import PermissionsFeature
import PreviewSupport
import ScoringFeature
import SharedModels
import Styleguide
import SubscriptionClient
import SwiftUI
import TeamEditingFeature
import WidgetSupport

package struct NewGameView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Bindable package var store: StoreOf<NewGameFeature>
  package var proAccess: SubscriptionEntitlement = .unknown

  package var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        DescribeGameView(store: store.scope(state: \.describeGame, action: \.describeGame))
          .disabled(store.isSaving)

        SetupSection("Teams") {
          NewGameTeamsView(store: store)
        }

        if let leftTeamName, let rightTeamName {
          SetupSection("Centre pass") {
            SetupCentrePassView(
              firstCentrePass: $store.firstCentrePass,
              leftTeamName: leftTeamName,
              rightTeamName: rightTeamName
            )
          }
        }

        SetupSection("Game details") {
          SetupGameDetailsView(store: store)
        }

        SetupSection("Timing") {
          SetupTimingSummaryView(timing: store.timing) { store.send(.editTimingButtonTapped) }
        }

        if proAccess != .unknown {
          SetupSection("Quarter alerts") {
            AlarmPermissionCard(
              store: store.scope(state: \.alarms, action: \.alarms),
              proAccess: proAccess,
              showsHeading: false
            )
          }
        }
        SetupSection("Location") {
          SetupLocationView(store: store)
        }

        SetupStartBar(
          canPrepareScoring: store.canPrepareScoring,
          configurationSummary: store.configurationSummary,
          errorMessage: store.teamNameErrorMessage ?? store.errorMessage,
          isSaving: store.isSaving,
          prepareScoringTapped: {
            store.send(store.scheduledAt == nil ? .prepareScoringButtonTapped : .saveGameButtonTapped)
          },
          isScheduled: store.scheduledAt != nil,
          prepareScoringNowTapped: { store.send(.prepareScoringButtonTapped) },
          retryTapped: { store.send(.retrySaveButtonTapped) },
          canRetry: store.failedSaveIntent != nil
        )
      }
      #if os(macOS)
      .frame(maxWidth: 680)
      .frame(maxWidth: .infinity)
      #endif
      .padding()
    }
    .scrollDismissesKeyboard(.interactively)
    .background(Color.setupBackground.ignoresSafeArea())
    .environment(\.usesGroupedSetupContainers, true)
    .navigationTitle("New game")
    .navigationBarBackButtonHidden()
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close", systemImage: "xmark") {
          store.send(.closeButtonTapped)
        }
        .disabled(store.isSaving)
      }
      ToolbarItem(placement: .primaryAction) {
        Button(
          store.scheduledAt == nil ? "Ready to score" : "Ready to score now",
          systemImage: "arrow.right"
        ) {
          store.send(.prepareScoringButtonTapped)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .disabled(!store.canPrepareScoring)
        .accessibilityIdentifier("gameSetup.prepareScoring")
      }
    }
    .onChange(of: store.draft) { _, _ in store.send(.configurationChanged) }
    .task { store.send(.task) }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        store.send(.sceneBecameActive)
      } else {
        store.send(.sceneBecameInactive)
      }
    }
    .sheet(
      item: $store.scope(state: \.destination, action: \.destination),
      onDismiss: { store.send(.destinationDidDismiss) }
    ) { destinationStore in
      switch destinationStore.case {
      case let .teamConfiguration(configurationStore):
        SetupTeamView(
          store: configurationStore.scope(
            state: \.configuration,
            action: \.configuration
          )
        )

      case let .teamPicker(pickerStore):
        NavigationStack {
          TeamPickerView(
            store: pickerStore.scope(
              state: \.picker,
              action: \.picker
            )
          )
          .navigationTitle("Select team")
          #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
          #endif
        }
        .presentationBackground(.thinMaterial)
        .presentationDetents([.medium, .large])

      case let .timingEditor(timingEditorStore):
        SetupTimingEditorView(store: timingEditorStore)
      }
    }
  }

  private var leftTeamName: String? {
    store.leftTeam.team?.name
  }

  private var rightTeamName: String? {
    store.rightTeam.team?.name
  }

  package init(
    store: StoreOf<NewGameFeature>, proAccess: SubscriptionEntitlement = .unknown
  ) {
    self.store = store
    self.proAccess = proAccess
  }
}

#Preview("Empty setup") {
  NavigationStack {
    NewGameView(store: setupPreviewStore())
  }
}

#Preview("Ready to start") {
  NavigationStack {
    NewGameView(store: setupPreviewStore(.previewReady))
  }
}

private struct SetupSection<Content: View>: View {
  let title: String
  @ViewBuilder var content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .accessibilityAddTraits(.isHeader)
      content
    }
  }
}
