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
    List {
      Group {
        DescribeGameView(store: store.scope(state: \.describeGame, action: \.describeGame))
          .disabled(store.isSaving)

        Section {
          TeamSlotsView(store: store)
        } header: {
          Text("Teams")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(.all, 0)

        if let leftTeamName, let rightTeamName {
          Section {
            CentrePassView(
              firstCentrePass: $store.firstCentrePass,
              leftTeamName: leftTeamName,
              rightTeamName: rightTeamName
            )
          } header: {
            Text("Centre pass")
          }
        }

        Section {
          GameDetailsView(store: store)
        } header: {
          Text("Game details")
        }

        Section("Timing") {
          SetupTimingSummaryView(timing: store.timing) { store.send(.editTimingButtonTapped) }

          if proAccess != .unknown {
            AlarmPermissionCard(
              store: store.scope(state: \.alarms, action: \.alarms),
              proAccess: proAccess,
              showsHeading: false
            )
          }
        }
        Section("Location") {
          SetupLocationView(store: store)
        }

        Section {
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
        .listRowBackground(Color.clear)
        .listRowInsets(.all, 0)
        .listRowSeparator(.hidden)
      }
      .environment(\.usesNativeSetupRows, true)
    }
    #if os(macOS)
    .frame(maxWidth: 680)
    .frame(maxWidth: .infinity)
    #endif
    #if os(iOS)
    .listStyle(.insetGrouped)
    #else
    .listStyle(.inset)
    #endif
    .scrollEdgeEffectStyle(.soft, for: .all)
    .scrollDismissesKeyboard(.interactively)
    .background(Color.setupBackground.ignoresSafeArea())
    .navigationTitle("New game")
    .navigationBarBackButtonHidden()
    .safeAreaBar(edge: .bottom, content: {
      if store.canPrepareScoring {
        Button {
          store.send(.prepareScoringButtonTapped)
        } label: {
          Text("Continue")
            .padding(8)
        }
        .buttonStyle(.glassProminent)
        .buttonSizing(.flexible)
        .padding()
      }
    })
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
    .onChange(of: scenePhase) { _, phase in scenePhaseChanged(phase) }
    .sheet(
      item: $store.scope(state: \.destination, action: \.destination)
    ) { destinationStore in
      switch destinationStore.case {
      case let .locationPicker(pickerStore):
        SetupLocationPickerView(store: pickerStore)

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

  private func scenePhaseChanged(_ phase: ScenePhase) {
    if phase == .active {
      store.send(.sceneBecameActive)
    } else {
      store.send(.sceneBecameInactive)
    }
  }

  private var leftTeamName: String? {
    store.leftTeam.team?.name
  }

  private var rightTeamName: String? {
    store.rightTeam.team?.name
  }

  package init(
    store: StoreOf<NewGameFeature>,
    proAccess: SubscriptionEntitlement = .unknown
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
