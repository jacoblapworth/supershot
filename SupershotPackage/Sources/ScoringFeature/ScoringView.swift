import AlarmClient
import AppSettings
import AppUI
import ComposableArchitecture
import Database
import Dependencies
import GameAnalysis
import GameCore
import GameServices
import PermissionsFeature
import PreviewSupport
import SharedModels
import SoundEffectsClient
import SQLiteData
import SubscriptionClient
import SwiftUI
import UI

package struct ScoringView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Fetch private var analysisResponse: GameAnalysisRequest.Value
  @State private var selectedAnalysis = GameAnalysisTab.playByPlay
  @State private var viewportHeight: CGFloat = 0
  @State private var controlsFrame = CGRect.zero
  @State private var scoringFrame = CGRect.zero
  @State private var isScoreboardAboveViewport = false
  @Bindable package var store: StoreOf<ScoringFeature>
  package let proAccess: SubscriptionEntitlement
  package let isPresentingPaywall: Bool

  package init(
    store: StoreOf<ScoringFeature>,
    proAccess: SubscriptionEntitlement = .unknown,
    isPresentingPaywall: Bool = false
  ) {
    self.isPresentingPaywall = isPresentingPaywall
    self.proAccess = proAccess
    self.store = store
    _analysisResponse = Fetch(
      wrappedValue: GameAnalysisRequest.Value(analysis: GameAnalysis(
        goalTimeline: .empty(through: store.period),
        periods: store.periods,
        teamABibColor: store.teamA.bibColor,
        teamAName: store.teamA.name,
        teamBBibColor: store.teamB.bibColor,
        teamBName: store.teamB.name
      )),
      GameAnalysisRequest(gameID: store.gameID),
      animation: .default
    )
  }

  package var body: some View {
    let scoreboard = ScoreboardView(courtLayout: store.courtLayout)

    ScrollView {
      LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
        VStack {
          TimerView(state: store.timerViewState) { store.send(.init(control: $0)) }

          scoreboard
            .onGeometryChange(for: Bool.self) { geometry in
              geometry.frame(in: .named("gameAnalysisViewport")).maxY <= 0
            } action: { isAboveViewport in
              isScoreboardAboveViewport = isAboveViewport
            }
        }
        .padding(.top)
        if store.scheduledAt != nil || store.court != nil {
          VStack(spacing: 8) {
            if let scheduledAt = store.scheduledAt {
              LabeledContent("Scheduled") {
                Text(scheduledAt.formatted(date: .abbreviated, time: .shortened))
              }
            }
            if let startedAt = store.startedAt {
              LabeledContent("Started") {
                Text(startedAt.formatted(date: .abbreviated, time: .shortened))
              }
            }
            if let court = store.court {
              LabeledContent("Court", value: court)
            }
          }
          .font(.subheadline)
          .padding()
          .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        #if os(macOS)
          AlarmPermissionCard(
            store: store.scope(state: \.alarms, action: \.alarms),
            proAccess: proAccess,
            hidesWhenAuthorized: true
          )
        #endif
        Section {
          GameAnalysisContentView(
            analysis: analysisResponse.analysis,
            selection: selectedAnalysis,
            teamAOnLeft: store.courtLayout.left.team.id == store.teamA.id,
            deleteGoal: store.canDeleteGoal ? { store.send(.deleteGoalButtonTapped($0)) } : nil
          )
          .frame(minHeight: max(viewportHeight - 68, 0), alignment: .top)
        } header: {
          GameAnalysisControl(selection: $selectedAnalysis)
        }
      }
      #if os(macOS)
      .frame(maxWidth: 960)
      .frame(maxWidth: .infinity)
      #endif
      .padding(.horizontal)
      .padding(.bottom)
    }
    .coordinateSpace(name: "gameAnalysisViewport")
    .onGeometryChange(for: CGFloat.self) {
      $0.size.height
    } action: {
      viewportHeight = $0
    }
    #if os(iOS)
    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
      scoringFrame = $0
    }
    .contentMargins(
      .bottom,
      controlsFrame == .zero ? 0 : max(0, scoringFrame.maxY - controlsFrame.minY),
      for: .scrollContent
    )
    #else
    .safeAreaInset(edge: .bottom, spacing: 0) {
      ScoringToolbarView(state: store.scoringToolbarState) { store.send(.init(control: $0)) }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .disabled(isPresentingPaywall || store.controlsPresentation != .shown)
    }
    #endif
    .background {
      TeamColorBackground(
        leftColor: store.courtLayout.left.team.bibColor,
        rightColor: store.courtLayout.right.team.bibColor
      )
      .ignoresSafeArea()
    }
    .preferredColorScheme(.dark)
    .toolbar {
      ToolbarItem(placement: .keyboard) {
        GlassEffectContainer {
          Text("test")
        }
      }
      ToolbarItem(placement: .principal) {
        if isScoreboardAboveViewport {
          ScoreboardHeaderView(left: scoreboard.left, right: scoreboard.right)
        }
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          store.send(.undoButtonTapped)
        } label: {
          Image(systemName: "arrow.uturn.backward")
        }
        .disabled(!store.canUndoGoal)
        .accessibilityLabel("Undo last goal")
      }

      ToolbarItem(placement: .primaryAction) {
        Menu {
          Button {
            store.send(.swapSidesButtonTapped)
          } label: {
            Label("Swap sides", systemImage: "arrow.left.arrow.right")
          }
          .disabled(store.isSavingCourtOrientation || !store.canOperate)

          Button {
            store.send(.changeCentrePassButtonTapped)
          } label: {
            Label("Change centre pass", systemImage: "arrow.left.circle.fill")
          }
          .disabled(!store.canOperate)

          Button("End Quarter", systemImage: "forward.end.fill") {
            store.send(.endQuarterButtonTapped)
          }
          .disabled(!store.canMoveToNextQuarter)

        } label: {
          Label("Options", systemImage: "ellipsis")
        }
      }
    }
    #if os(iOS)
    .sheet(
      isPresented: .constant(store.controlsPresentation == .shown && !isPresentingPaywall),
      onDismiss: { store.send(.controlsSheetDidDismiss) }
    ) {
      ScoringToolbarView(
        state: store.scoringToolbarState,
        onAction: { store.send(.init(control: $0)) },
        onFrameChange: { controlsFrame = $0 }
      )
    }
    .overlay {
      GeometryReader { geometry in
        if case let .confirmation(confirmation) = store.scoringToolbarState.content,
           store.controlsPresentation == .shown, !isPresentingPaywall, controlsFrame != .zero
        {
          LastCentrePassBanner(availability: confirmation.availability) {
            store.send(.centrePassConfirmed($0))
          }
          .id(confirmation.period)
          .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32))
          .frame(width: max(0, controlsFrame.width - 16))
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxHeight: .infinity, alignment: .bottom)
          .frame(height: max(0, controlsFrame.minY - geometry.frame(in: .global).minY - 8))
          .offset(x: controlsFrame.minX - geometry.frame(in: .global).minX + 8)
        }
      }
    }
    #endif
    .sheet(
      item: $store.scope(state: \.timeInput, action: \.timeInput),
      onDismiss: { store.send(.timeInputSheetDidDismiss) }
    ) { TimeInputView(store: $0) }
    .alert($store.scope(state: \.alert, action: \.alert))
    .onChange(of: isPresentingPaywall) { wasPresented, isPresented in
      if wasPresented, !isPresented {
        store.send(.proPaywallDidDismiss)
      }
    }
    .onChange(of: proAccess) { _, access in
      if access == .pro {
        store.send(.proPaywallDidDismiss)
      }
    }
    #if os(iOS)
    .sensoryFeedback(
      .success,
      trigger: store.goalFeedbackTrigger,
      condition: { _, _ in store.hapticsEnabled }
    )
    #endif
    .task(id: scenePhase) {
      guard scenePhase == .active else { return }
      await store.send(.keepScreenAwakeTask).finish()
    }
    .task {
      guard scenePhase == .active else { return }
      store.send(.sceneBecameActive)
    }
    .onChange(of: scenePhase, scenePhaseChanged)
    #if os(macOS)
      .focusedSceneValue(\.scoringCommands, ScoringCommandContext(store: store, isPresentingPaywall: isPresentingPaywall))
    #endif
  }

  private func scenePhaseChanged(
    _: ScenePhase,
    _ newValue: ScenePhase
  ) {
    store.send(newValue == .active ? .sceneBecameActive : .sceneBecameInactive)
  }
}

#Preview("Scoring scenarios") {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.defaultDatabase.seedDebugExamplesIfNeeded()
  }
  ScoringScenarioPreview()
}

private struct ScoringScenarioPreview: View {
  @State private var scenario = ScoringPreviewScenario.running

  var body: some View {
    NavigationStack {
      ScoringView(store: scoringPreviewStore(scenario.state))
        .id(scenario)
        .toolbar {
          ToolbarItem(placement: .automatic) {
            Picker("Scenario", selection: $scenario) {
              ForEach(ScoringPreviewScenario.allCases) { Text($0.rawValue).tag($0) }
            }
          }
        }
    }
  }
}
